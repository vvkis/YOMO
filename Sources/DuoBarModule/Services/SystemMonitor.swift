import Foundation
import AppKit
import Darwin
import SystemConfiguration

final class SystemMonitor: @unchecked Sendable {
    private let stateLock = NSLock()
    private var prevCPUTicks: host_cpu_load_info?
    private var prevNetBytes: (iface: String, rx: UInt64, tx: UInt64, time: TimeInterval)?
    private var cachedRouteInfo: (ip: String, iface: String, connected: Bool, time: TimeInterval)?
    private var cpuHistory: [Double] = Array(repeating: 0, count: 24)
    private let dynamicStore: SCDynamicStore?

    private let processLock = NSLock()
    private var prevProcCPUNs: [pid_t: UInt64] = [:]
    private var prevProcSampleTime: TimeInterval?
    private let machTimebaseNumer: UInt64
    private let machTimebaseDenom: UInt64

    init() {
        var info = mach_timebase_info_data_t(numer: 1, denom: 1)
        mach_timebase_info(&info)
        self.machTimebaseNumer = UInt64(max(1, info.numer))
        self.machTimebaseDenom = UInt64(max(1, info.denom))
        self.dynamicStore = SCDynamicStoreCreate(nil, "YOMO.Network" as CFString, nil, nil)
    }

    func sampleCPU() -> CPUStats {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &size)
            }
        }

        var userPct = 0.0
        var sysPct = 0.0
        var totalPct = 0.0

        stateLock.lock()
        if result == KERN_SUCCESS {
            if let prev = prevCPUTicks {
                let dUser = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
                let dSys  = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
                let dIdle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
                let dNice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
                let total = dUser + dSys + dIdle + dNice
                if total > 0 {
                    userPct = ((dUser + dNice) / total) * 100.0
                    sysPct  = (dSys / total) * 100.0
                    totalPct = min(100.0, max(0.0, userPct + sysPct))
                }
            }
            prevCPUTicks = info
        }

        cpuHistory.append(totalPct)
        if cpuHistory.count > 24 {
            cpuHistory.removeFirst(cpuHistory.count - 24)
        }
        let historySnapshot = cpuHistory
        stateLock.unlock()

        var loadAvg = [Double](repeating: 0, count: 3)
        getloadavg(&loadAvg, 3)

        return CPUStats(
            totalUsage: totalPct,
            userUsage: userPct,
            systemUsage: sysPct,
            loadAverage: String(format: "%.2f", loadAvg[0]),
            history: historySnapshot
        )
    }

    func sampleMemory() -> MemoryStats {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalBytes / 1_073_741_824.0

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            return MemoryStats(totalGB: totalGB)
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = Double(pageSize)

        let appPages = max(0.0, Double(vmStats.internal_page_count) - Double(vmStats.purgeable_count))
        let wiredPages = Double(vmStats.wire_count)
        let compressedPages = Double(vmStats.compressor_page_count)

        let activeGB = (appPages * ps) / 1_073_741_824.0
        let wiredGB = (wiredPages * ps) / 1_073_741_824.0
        let compressedGB = (compressedPages * ps) / 1_073_741_824.0
        let usedGB = min(totalGB, activeGB + wiredGB + compressedGB)
        let usagePct = totalGB > 0 ? min(100.0, max(0.0, (usedGB / totalGB) * 100.0)) : 0.0

        let pressure = readKernelMemoryPressure()

        return MemoryStats(
            usagePercent: usagePct,
            usedGB: usedGB,
            totalGB: totalGB,
            activeGB: activeGB,
            wiredGB: wiredGB,
            compressedGB: compressedGB,
            pressureLevel: pressure
        )
    }

    private func readKernelMemoryPressure() -> MemoryStats.Pressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            if level >= 4 { return .critical }
            if level >= 2 { return .warning }
        }
        return .normal
    }

    func sampleDisk() -> DiskStats {
        let rootURL = URL(fileURLWithPath: "/")
        guard let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else {
            return DiskStats()
        }

        let total = Double(values.volumeTotalCapacity ?? 0)
        let avail: Double
        if let important = values.volumeAvailableCapacityForImportantUsage {
            avail = Double(important)
        } else {
            avail = Double(values.volumeAvailableCapacity ?? 0)
        }

        guard total > 0 else { return DiskStats() }
        let used = max(0, total - avail)
        let gbDivisor = 1_000_000_000.0
        let totalGB = total / gbDivisor
        let usedGB = used / gbDivisor
        let availGB = avail / gbDivisor
        let pct = min(100.0, max(0.0, (used / total) * 100.0))

        return DiskStats(
            usagePercent: pct,
            usedGB: usedGB,
            totalGB: totalGB,
            availableGB: availGB
        )
    }

    /// Reads 64-bit interface byte counters via `sysctl(NET_RT_IFLIST2)` on every tick,
    /// while caching the primary interface & IPv4 lookup (`SCDynamicStore` + `getifaddrs`)
    /// so background ticks don't repeatedly walk `getifaddrs`.
    func sampleNetwork(forceRouteRefresh: Bool = false) -> NetworkStats {
        let now = Date().timeIntervalSinceReferenceDate

        stateLock.lock()
        let cached = cachedRouteInfo
        stateLock.unlock()

        let detectedIP: String
        let targetIface: String
        let connected: Bool

        if !forceRouteRefresh, let cached, (now - cached.time) < 15.0 {
            detectedIP = cached.ip
            targetIface = cached.iface
            connected = cached.connected
        } else {
            let primaryIface = readSystemPrimaryInterface()
            let (ip, activeIface, isConn) = readActiveIPv4(preferredInterface: primaryIface)
            let resolvedIface = !activeIface.isEmpty ? activeIface : primaryIface
            detectedIP = ip
            targetIface = resolvedIface
            connected = isConn

            stateLock.lock()
            cachedRouteInfo = (ip: detectedIP, iface: targetIface, connected: connected, time: now)
            stateLock.unlock()
        }

        let (totalRx, totalTx) = read64BitInterfaceBytes(targetInterface: targetIface)

        var downSpeed = 0.0
        var upSpeed = 0.0

        stateLock.lock()
        if let prev = prevNetBytes, prev.iface == targetIface {
            let dt = now - prev.time
            if dt > 0.1 {
                let dRx = totalRx >= prev.rx ? Double(totalRx - prev.rx) : 0
                let dTx = totalTx >= prev.tx ? Double(totalTx - prev.tx) : 0
                downSpeed = dRx / dt
                upSpeed = dTx / dt
            }
        }
        prevNetBytes = (targetIface, totalRx, totalTx, now)
        stateLock.unlock()

        return NetworkStats(
            uploadBytesPerSec: upSpeed,
            downloadBytesPerSec: downSpeed,
            localIP: detectedIP,
            isConnected: connected,
            activeInterface: targetIface
        )
    }

    private func readSystemPrimaryInterface() -> String {
        guard let store = dynamicStore else {
            return ""
        }
        if let ipv4State = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let primary = ipv4State["PrimaryInterface"] as? String,
           !primary.isEmpty {
            return primary
        }
        if let ipv6State = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any],
           let primary = ipv6State["PrimaryInterface"] as? String,
           !primary.isEmpty {
            return primary
        }
        return ""
    }

    private func read64BitInterfaceBytes(targetInterface: String) -> (rx: UInt64, tx: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else {
            return (0, 0)
        }

        var buffer = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &len, nil, 0) == 0 else {
            return (0, 0)
        }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        var nameBuf = [CChar](repeating: 0, count: Int(IFNAMSIZ))

        buffer.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr.self).pointee
                let msgLen = Int(hdr.ifm_msglen)
                guard msgLen > 0, offset + msgLen <= len else { break }

                if Int32(hdr.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= len {
                    let hdr2 = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self).pointee
                    let flags = hdr2.ifm_flags
                    let isUp = (flags & IFF_UP) != 0
                    let isRunning = (flags & IFF_RUNNING) != 0
                    let isLoopback = (flags & IFF_LOOPBACK) != 0

                    if isUp && isRunning && !isLoopback,
                       if_indextoname(UInt32(hdr2.ifm_index), &nameBuf) != nil {
                        let name = String(cString: nameBuf)
                        if !targetInterface.isEmpty {
                            if name == targetInterface {
                                totalRx &+= hdr2.ifm_data.ifi_ibytes
                                totalTx &+= hdr2.ifm_data.ifi_obytes
                            }
                        } else if !name.hasPrefix("utun") && !name.hasPrefix("llw") && !name.hasPrefix("awdl") && !name.hasPrefix("bridge") {
                            totalRx &+= hdr2.ifm_data.ifi_ibytes
                            totalTx &+= hdr2.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += msgLen
            }
        }

        return (totalRx, totalTx)
    }

    private func readActiveIPv4(preferredInterface: String) -> (ip: String, iface: String, connected: Bool) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return ("--", preferredInterface, false)
        }
        defer { freeifaddrs(ifaddrPtr) }

        var detectedIP = "--"
        var activeIface = preferredInterface
        var connected = false

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let iface = current.pointee
            let name = String(cString: iface.ifa_name)
            let flags = Int32(iface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && isRunning && !isLoopback,
               let addr = iface.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    if !ip.hasPrefix("169.254.") && !ip.hasPrefix("127.") {
                        connected = true
                        if !preferredInterface.isEmpty && name == preferredInterface {
                            return (ip, name, true)
                        }
                        if detectedIP == "--" {
                            detectedIP = ip
                            activeIface = name
                        }
                    }
                }
            }
            ptr = iface.ifa_next
        }
        return (detectedIP, activeIface, connected)
    }

    // MARK: - On-Demand Top Process Sampling (100% kernel proc_pid_rusage, zero /bin/ps subprocess)

    func resetProcessSampler() {
        processLock.lock()
        prevProcCPUNs.removeAll()
        prevProcSampleTime = nil
        processLock.unlock()
    }

    func sampleTopProcesses(limit: Int = 6) -> (topCPU: [ProcessStatItem], topMemory: [ProcessStatItem]) {
        var appMetaByPID: [pid_t: (name: String, icon: NSImage?)] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            if pid > 0 {
                let name = app.localizedName ?? app.bundleIdentifier ?? ""
                if !name.isEmpty {
                    appMetaByPID[pid] = (name, app.icon)
                }
            }
        }

        let pids = listAllPIDs()
        guard !pids.isEmpty else { return ([], []) }

        processLock.lock()
        var prevTimes = prevProcCPUNs
        var prevTime = prevProcSampleTime
        processLock.unlock()

        var now = Date().timeIntervalSinceReferenceDate
        var dt = prevTime.map { now - $0 } ?? 0

        if dt <= 0.20 || prevTimes.isEmpty {
            prevTimes = captureCPUNanoseconds(for: pids)
            prevTime = Date().timeIntervalSinceReferenceDate
            Thread.sleep(forTimeInterval: 0.35)
            now = Date().timeIntervalSinceReferenceDate
            dt = now - (prevTime ?? now)
        }

        var nextTimes: [pid_t: UInt64] = [:]
        nextTimes.reserveCapacity(pids.count)

        var rawItems: [(pid: pid_t, name: String, cpu: Double, mem: UInt64, icon: NSImage?)] = []
        rawItems.reserveCapacity(pids.count)

        for pid in pids {
            var rinfo = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &rinfo) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard rc == 0 else { continue }

            let memBytes = rinfo.ri_phys_footprint
            let totalMach = rinfo.ri_user_time &+ rinfo.ri_system_time
            let totalNs = (totalMach / machTimebaseDenom) &* machTimebaseNumer
            nextTimes[pid] = totalNs

            let cpuPct: Double
            if dt > 0.1, let prevNs = prevTimes[pid], totalNs >= prevNs {
                let deltaNs = Double(totalNs - prevNs)
                cpuPct = (deltaNs / (dt * 1_000_000_000.0)) * 100.0
            } else {
                cpuPct = 0.0
            }

            if memBytes < 5_000_000 && cpuPct < 0.1 { continue }

            let meta = appMetaByPID[pid]
            let resolvedName: String
            if let appName = meta?.name, !appName.isEmpty {
                resolvedName = appName
            } else if let procName = Self.readProcessName(pid: pid), !procName.isEmpty {
                resolvedName = procName
            } else {
                resolvedName = "PID \(pid)"
            }

            rawItems.append((pid: pid, name: resolvedName, cpu: cpuPct, mem: memBytes, icon: meta?.icon))
        }

        processLock.lock()
        prevProcCPUNs = nextTimes
        prevProcSampleTime = now
        processLock.unlock()

        let topCPU = rawItems
            .sorted { $0.cpu > $1.cpu }
            .prefix(limit)
            .map { ProcessStatItem(pid: $0.pid, name: $0.name, cpuPercent: $0.cpu, memoryBytes: $0.mem, icon: $0.icon) }

        let topMem = rawItems
            .sorted { $0.mem > $1.mem }
            .prefix(limit)
            .map { ProcessStatItem(pid: $0.pid, name: $0.name, cpuPercent: $0.cpu, memoryBytes: $0.mem, icon: $0.icon) }

        return (Array(topCPU), Array(topMem))
    }

    private func listAllPIDs() -> [pid_t] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(estimatedCount) + 64)
        let bytesReturned = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard bytesReturned > 0 else { return [] }
        let actualCount = Int(bytesReturned) / MemoryLayout<pid_t>.stride

        var seen = Set<pid_t>()
        seen.reserveCapacity(actualCount)
        var result: [pid_t] = []
        result.reserveCapacity(actualCount)
        for i in 0..<actualCount {
            let pid = pids[i]
            if pid > 0 && seen.insert(pid).inserted {
                result.append(pid)
            }
        }
        return result
    }

    private func captureCPUNanoseconds(for pids: [pid_t]) -> [pid_t: UInt64] {
        var map: [pid_t: UInt64] = [:]
        map.reserveCapacity(pids.count)
        for pid in pids {
            var rinfo = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &rinfo) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            if rc == 0 {
                let totalMach = rinfo.ri_user_time &+ rinfo.ri_system_time
                map[pid] = (totalMach / machTimebaseDenom) &* machTimebaseNumer
            }
        }
        return map
    }

    private static func readProcessName(pid: pid_t) -> String? {
        var nameBuf = [CChar](repeating: 0, count: 256)
        let len = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        if len > 0 {
            let s = String(cString: nameBuf)
            if !s.isEmpty { return s }
        }
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        if pLen > 0 {
            let full = String(cString: pathBuf)
            return URL(fileURLWithPath: full).lastPathComponent
        }
        return nil
    }
}

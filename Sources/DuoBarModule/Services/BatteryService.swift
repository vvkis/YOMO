import Foundation
import AppKit
import IOKit
import IOKit.ps

final class BatteryService: @unchecked Sendable {
    var onPowerSourceChanged: (@Sendable () -> Void)?
    private var runLoopSource: CFRunLoopSource?
    private var lpmObserver: NSObjectProtocol?

    init() {
        setupNotifications()
    }

    deinit {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        if let lpmObserver {
            NotificationCenter.default.removeObserver(lpmObserver)
        }
    }

    private func setupNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            service.onPowerSourceChanged?()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = source
        }

        lpmObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onPowerSourceChanged?()
        }
    }

    func sampleBattery() -> BatteryStats {
        var stats = BatteryStats()
        stats.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // 1. High-level IOPS power source info
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] {

            stats.hasBattery = true
            let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
            let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
            if maxCap > 0 {
                stats.percentage = min(100, max(0, Int((Double(current) / Double(maxCap)) * 100.0)))
            }

            let source = desc[kIOPSPowerSourceStateKey as String] as? String ?? ""
            stats.isPluggedIn = (source == kIOPSACPowerValue as String)
            stats.isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            stats.isCharged = (desc[kIOPSIsChargedKey as String] as? Bool) ?? false

            let timeToEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int ?? -1
            let timeToFull = desc[kIOPSTimeToFullChargeKey as String] as? Int ?? -1

            if stats.isCharging {
                if timeToFull > 0 {
                    stats.timeRemainingText = "充满约 \(formatMinutes(timeToFull))"
                } else {
                    stats.timeRemainingText = "正在充电"
                }
            } else if stats.isPluggedIn {
                stats.timeRemainingText = stats.isCharged ? "已充满" : "已接通电源"
            } else {
                if timeToEmpty > 0 {
                    stats.timeRemainingText = "剩余约 \(formatMinutes(timeToEmpty))"
                } else {
                    stats.timeRemainingText = "估算中…"
                }
            }
        } else {
            // Desktop Mac without internal battery
            stats.hasBattery = false
            stats.percentage = 100
            stats.isPluggedIn = true
            stats.isCharged = true
            stats.timeRemainingText = "电源供电"
        }

        // 2. Detailed IORegistry AppleSmartBattery info (cycles, health, wattage)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propsRef?.takeRetainedValue() as? [String: Any] {

                if let cycles = dict["CycleCount"] as? Int {
                    stats.cycleCount = cycles
                }

                let designCap = (dict["DesignCapacity"] as? Double)
                    ?? (dict["BatteryData"] as? [String: Any])?["DesignCapacity"] as? Double
                    ?? 0
                let rawMaxCap = (dict["AppleRawMaxCapacity"] as? Double)
                    ?? (dict["NominalChargeCapacity"] as? Double)
                    ?? (dict["BatteryData"] as? [String: Any])?["AppleRawMaxCapacity"] as? Double
                    ?? 0

                if designCap > 0 && rawMaxCap > 0 {
                    stats.healthPercent = min(100, max(1, Int(round((rawMaxCap / designCap) * 100.0))))
                }

                if stats.isPluggedIn,
                   let adapter = dict["AdapterDetails"] as? [String: Any],
                   let ratedW = adapter["Watts"] as? Int,
                   ratedW > 0 {
                    stats.adapterRatedWatts = ratedW
                }

                if let telemetry = dict["PowerTelemetryData"] as? [String: Any] {
                    if let sysLoadNum = telemetry["SystemLoad"] as? NSNumber {
                        let mw = sysLoadNum.int64Value
                        if mw > 0 {
                            stats.systemLoadWatts = Double(mw) / 1000.0
                        }
                    }
                    if stats.isPluggedIn, let sysInNum = telemetry["SystemPowerIn"] as? NSNumber {
                        let mw = sysInNum.int64Value
                        if mw > 0 {
                            stats.systemPowerInWatts = Double(mw) / 1000.0
                        }
                    }
                }
            }
        }

        return stats
    }

    func setLowPowerMode(enabled: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        let target = enabled ? "1" : "0"
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptSource = "do shell script \"/usr/bin/pmset -a lowpowermode \(target)\" with administrator privileges"
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                _ = script.executeAndReturnError(&errorInfo)
                let ok = (errorInfo == nil)
                DispatchQueue.main.async {
                    completion(ok)
                }
            } else {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

    func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func formatMinutes(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}

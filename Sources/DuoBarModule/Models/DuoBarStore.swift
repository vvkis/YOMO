import Foundation
import Combine
import AppKit
import ServiceManagement
import CoreKit

public enum PopoverPage: Equatable {
    case overview
    case wifi
    case battery
    case telemetry
    case audioBluetooth
    case display
    case keepAwake
    case scrollReverser
    case clipboard
    case spaceCleaner
    case settings
}

@MainActor
public final class DuoBarStore: ObservableObject {
    @Published public var cpu = CPUStats()
    @Published public var memory = MemoryStats()
    @Published public var disk = DiskStats()
    @Published public var network = NetworkStats()
    @Published public var battery = BatteryStats()
    @Published public var wifi = WiFiState()
    @Published public var isTogglingLPM = false
    @Published public var launchAtLogin = false
    @Published public var currentPage: PopoverPage = .overview
    @Published public var isGoingForward = true
    @Published public var showOtherNetworks = false
    @Published public var passwordTargetSSID: String? = nil
    @Published public var passwordInput: String = ""

    // On-demand System Telemetry state (sampled ONLY while currentPage == .telemetry)
    @Published public var telemetryTab: TelemetrySortTab = .cpu {
        didSet {
            if telemetryTab == .ports && currentPage == .telemetry {
                refreshListeningPorts()
            } else if telemetryTab != .ports {
                pendingKillPortID = nil
                if currentPage == .telemetry {
                    refreshTopProcesses()
                }
            }
        }
    }
    @Published public var topCPUProcesses: [ProcessStatItem] = []
    @Published public var topMemoryProcesses: [ProcessStatItem] = []
    @Published public var isLoadingProcesses: Bool = false

    // On-demand Listening Port Radar state (sampled ONLY while telemetryTab == .ports)
    @Published public var listeningPorts: [ListeningPortItem] = []
    @Published public var isLoadingPorts: Bool = false
    @Published public var portSearchQuery: String = ""
    @Published public var pendingKillPortID: String? = nil
    @Published public var forceKillEligiblePIDs: Set<Int32> = []
    @Published public var portActionFeedback: String? = nil

    /// Latest sampled snapshots used by StatusBadgeRenderer even when popover/console UI is hidden,
    /// avoiding unnecessary SwiftUI view-tree diffs on background ticks.
    public private(set) var latestCPU = CPUStats()
    public private(set) var latestMemory = MemoryStats()
    public private(set) var latestDisk = DiskStats()
    public private(set) var latestNetwork = NetworkStats()
    public private(set) var latestBattery = BatteryStats()
    public private(set) var latestWiFi = WiFiState()

    public let prefs = AppPreferences()

    private let systemMonitor = SystemMonitor()
    private let batteryService = BatteryService()
    private let wifiService = WiFiService()
    private let telemetryQueue = DispatchQueue(label: "com.yomo.duobar.telemetry", qos: .utility)

    private var timer: Timer?
    private var tickCount = 0
    private var isPopoverOpen = false
    private var isConsoleOpen = false
    private var isScreenAsleep = false
    private var isSamplingTelemetry = false
    private var pendingHeavyRefresh = false
    private var pendingForcePublish = false
    private var isSamplingBattery = false
    private var isSamplingWiFi = false
    private var isSamplingProcesses = false
    private var isSamplingPorts = false
    private var pendingKillResetWork: DispatchWorkItem?
    private var portFeedbackResetWork: DispatchWorkItem?
    private var pendingBatteryRefreshWork: DispatchWorkItem?
    private var pendingWiFiRefreshWork: DispatchWorkItem?
    /// Event-triggered, bounded confirmation re-samples after a power-source change.
    /// IOPS flips `PowerSourceState` to AC immediately on plug-in, but `IsCharging` only settles after
    /// USB-PD / SMC negotiation (often 1–5 s later) and may not emit a further notification.
    private var powerSettleWork: DispatchWorkItem?
    private var powerSettleStep = Int.max  // idle until the first power event opens the window
    private var powerSettleLastSignature: PowerSignature?
    private static let powerSettleDelays: [TimeInterval] = [0.6, 1.5, 3.0, 5.0]
    private var lastWiFiEventSampleTime: TimeInterval = 0
    private var lastBatteryEventSampleTime: TimeInterval = 0
    private var lastRefreshInterval: Double = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    public var onStatusBarNeedsRedraw: (() -> Void)?

    private var isUIActive: Bool {
        isPopoverOpen || isConsoleOpen
    }

    public init() {
        refreshLaunchAtLoginState()
        setupSleepWakeObservers()

        batteryService.onPowerSourceChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isScreenAsleep else { return }
                self.beginPowerSettle()
                self.refreshBatteryState(throttled: true)
            }
        }

        wifiService.onWiFiEventChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isScreenAsleep else { return }
                self.refreshWiFiQuickState(throttled: true)
                if self.isPopoverOpen && self.currentPage == .wifi && !self.wifi.isScanning {
                    self.scanNearbyWiFi()
                }
            }
        }

        wifiService.onAuthorizationChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isScreenAsleep else { return }
                self.refreshWiFiQuickState(throttled: false)
                if self.isPopoverOpen && self.currentPage == .wifi {
                    self.scanNearbyWiFi()
                }
            }
        }

        wifiService.startMonitoring()

        lastRefreshInterval = prefs.refreshInterval
        prefs.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.prefs.refreshInterval != self.lastRefreshInterval {
                        self.lastRefreshInterval = self.prefs.refreshInterval
                        self.restartTimer()
                    }
                    self.onStatusBarNeedsRedraw?()
                }
            }
            .store(in: &cancellables)

        refreshAll(includeHeavy: true, forcePublish: true)
        restartTimer()
    }

    deinit {
        timer?.invalidate()
        powerSettleWork?.cancel()
        pendingBatteryRefreshWork?.cancel()
        pendingWiFiRefreshWork?.cancel()
        pendingKillResetWork?.cancel()
        portFeedbackResetWork?.cancel()
        let nc = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            nc.removeObserver(obs)
        }
    }

    private func setupSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let sleepNames: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification
        ]
        let wakeNames: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification
        ]

        for name in sleepNames {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isScreenAsleep = true
                    self.timer?.invalidate()
                    self.timer = nil
                    self.powerSettleWork?.cancel()
                    self.powerSettleWork = nil
                    self.powerSettleStep = Int.max
                    self.powerSettleLastSignature = nil
                    self.pendingBatteryRefreshWork?.cancel()
                    self.pendingBatteryRefreshWork = nil
                    self.pendingWiFiRefreshWork?.cancel()
                    self.pendingWiFiRefreshWork = nil
                }
            }
            workspaceObservers.append(obs)
        }

        for name in wakeNames {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let notifName = note.name
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Ignore macOS Dark Wake (Power Nap) when displays remain asleep so background timers stay dead-quiet
                    if notifName == NSWorkspace.didWakeNotification && DisplayPowerState.areAllDisplaysAsleep() {
                        return
                    }
                    self.isScreenAsleep = false
                    self.refreshAll(includeHeavy: self.isUIActive, forcePublish: self.isUIActive)
                    self.restartTimer()
                }
            }
            workspaceObservers.append(obs)
        }
    }

    public func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard !isScreenAsleep else { return }

        let interval = max(1.0, prefs.refreshInterval)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        // 20% tolerance lets macOS kernel coalesce timer wakeups for near-zero idle energy impact
        newTimer.tolerance = interval * 0.2
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        guard !isScreenAsleep else { return }
        tickCount += 1
        // While popover/console is closed, rely 100% on system events for Wi-Fi & Battery,
        // and only sample lightweight kernel Mach/sysctl counters (CPU / Memory / Network bytes).
        let style = prefs.badgeStyle
        let includeCPU = isUIActive || style == .dualRing || style == .triArc
        let includeNetwork = isUIActive || style == .capsule
        let includeDisk = isUIActive && (tickCount % 15 == 0)
        let includeWiFiSignal = isUIActive && ((tickCount % 3 == 0) || currentPage == .wifi)
        let needsBatteryEstimateRefresh = isPopoverOpen
            && !latestBattery.isPluggedIn
            && !latestBattery.timeRemainingText.hasPrefix("剩余约")
            && (tickCount % 3 == 0)
        let includeBattery = (isPopoverOpen && currentPage == .battery) || needsBatteryEstimateRefresh
        let includeDetailedBattery = includeBattery
        sampleTelemetryAsync(
            includeCPU: includeCPU,
            includeNetwork: includeNetwork,
            includeDisk: includeDisk,
            includeBattery: includeBattery,
            includeDetailedBattery: includeDetailedBattery,
            includeWiFi: includeWiFiSignal,
            forceRouteRefresh: false,
            forcePublish: false
        )
        if isPopoverOpen && currentPage == .telemetry {
            if telemetryTab == .ports {
                if tickCount % 3 == 0 {
                    refreshListeningPorts()
                }
            } else {
                refreshTopProcesses()
            }
        }
    }

    public func refreshAll(includeHeavy: Bool = false, forcePublish: Bool = false) {
        sampleTelemetryAsync(
            includeCPU: true,
            includeNetwork: true,
            includeDisk: includeHeavy || latestDisk.totalGB == 0,
            includeBattery: true,
            includeDetailedBattery: includeHeavy || isUIActive,
            includeWiFi: true,
            forceRouteRefresh: includeHeavy,
            forcePublish: forcePublish
        )
    }

    private func publishLatestSnapshotsToUI() {
        cpu = latestCPU
        memory = latestMemory
        disk = latestDisk
        network = latestNetwork
        battery = latestBattery
        wifi = latestWiFi
    }

    private func refreshBatteryState(throttled: Bool = false) {
        guard !isScreenAsleep else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = now - lastBatteryEventSampleTime
        if isSamplingBattery || (throttled && elapsed < 0.45) {
            // Trailing-edge coalescing: NEVER silently drop the final settled state during a
            // MagSafe/USB-C plug-in burst (1st event often has IsCharging=0, 2nd has IsCharging=1 ~200ms later).
            let delay = isSamplingBattery ? 0.25 : max(0.15, 0.45 - elapsed)
            pendingBatteryRefreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshBatteryState(throttled: false)
                }
            }
            pendingBatteryRefreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return
        }

        pendingBatteryRefreshWork?.cancel()
        pendingBatteryRefreshWork = nil
        isSamplingBattery = true
        lastBatteryEventSampleTime = now

        let batSvc = batteryService
        let prevBat = latestBattery
        let detailed = isUIActive
        telemetryQueue.async { [weak self] in
            let bat = batSvc.sampleBattery(includeDetailedIORegistry: detailed, previous: prevBat)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSamplingBattery = false
                let mergedBat = detailed ? bat : mergeDetailedBatteryFields(from: self.latestBattery, into: bat)
                self.latestBattery = mergedBat
                if self.isUIActive {
                    self.battery = mergedBat
                }
                self.onStatusBarNeedsRedraw?()
                self.scheduleNextPowerSettleIfNeeded(after: mergedBat)
            }
        }
    }

    // MARK: - Power settle window

    private struct PowerSignature: Equatable {
        let isPluggedIn: Bool
        let isCharging: Bool
        let isCharged: Bool
    }

    /// Called on every IOPS / LPM event: (re)opens a short, bounded confirmation window.
    private func beginPowerSettle() {
        powerSettleWork?.cancel()
        powerSettleWork = nil
        powerSettleStep = 0
        powerSettleLastSignature = nil
    }

    /// After each battery sample, schedule the next confirmation re-sample until the
    /// charging state is consistent and stable, or the window (≈10 s total) is exhausted.
    /// Uses its own work item so trailing-edge throttling can never cancel it.
    private func scheduleNextPowerSettleIfNeeded(after bat: BatteryStats) {
        let sig = PowerSignature(isPluggedIn: bat.isPluggedIn, isCharging: bat.isCharging, isCharged: bat.isCharged)
        let stable = (sig == powerSettleLastSignature)
        powerSettleLastSignature = sig
        // Unplugged ⇒ never charging; plugged ⇒ either charging or full. Anything else (AC but not
        // yet charging, or battery still reporting charging on battery power) is a transient state.
        let consistent = sig.isPluggedIn ? (sig.isCharging || sig.isCharged) : !sig.isCharging
        let delays = Self.powerSettleDelays
        if (consistent && stable) || powerSettleStep >= delays.count {
            powerSettleWork?.cancel()
            powerSettleWork = nil
            powerSettleStep = Int.max
            powerSettleLastSignature = nil
            return
        }
        let delay = delays[powerSettleStep]
        powerSettleStep += 1
        powerSettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshBatteryState(throttled: false)
            }
        }
        powerSettleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refreshWiFiQuickState(throttled: Bool = false) {
        guard !isScreenAsleep else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = now - lastWiFiEventSampleTime
        if isSamplingWiFi || (throttled && elapsed < 0.50) {
            let delay = isSamplingWiFi ? 0.25 : max(0.15, 0.50 - elapsed)
            pendingWiFiRefreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshWiFiQuickState(throttled: false)
                }
            }
            pendingWiFiRefreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return
        }

        pendingWiFiRefreshWork?.cancel()
        pendingWiFiRefreshWork = nil
        isSamplingWiFi = true
        lastWiFiEventSampleTime = now

        let wifiSvc = wifiService
        let prevWiFi = latestWiFi
        let mon = systemMonitor
        telemetryQueue.async { [weak self] in
            let nextWiFi = wifiSvc.sampleQuickState(previous: prevWiFi)
            let nextNet = mon.sampleNetwork(forceRouteRefresh: true)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSamplingWiFi = false
                let merged = mergeWiFiLists(from: self.latestWiFi, into: nextWiFi)
                self.latestWiFi = merged
                self.latestNetwork = nextNet
                if self.isUIActive {
                    self.wifi = merged
                    self.network = nextNet
                }
                self.onStatusBarNeedsRedraw?()
            }
        }
    }

    private func sampleTelemetryAsync(
        includeCPU: Bool,
        includeNetwork: Bool,
        includeDisk: Bool,
        includeBattery: Bool,
        includeDetailedBattery: Bool,
        includeWiFi: Bool,
        forceRouteRefresh: Bool,
        forcePublish: Bool
    ) {
        guard !isSamplingTelemetry else {
            if includeDisk || includeDetailedBattery || forcePublish {
                pendingHeavyRefresh = pendingHeavyRefresh || includeDisk || includeDetailedBattery
                pendingForcePublish = pendingForcePublish || forcePublish
            }
            return
        }
        isSamplingTelemetry = true

        let mon = systemMonitor
        let batSvc = batteryService
        let wifiSvc = wifiService
        let prevBat = latestBattery
        let prevWiFi = latestWiFi

        telemetryQueue.async { [weak self] in
            let nextCPU: CPUStats? = includeCPU ? mon.sampleCPU() : nil
            let nextMem = mon.sampleMemory()
            let nextNet: NetworkStats? = includeNetwork ? mon.sampleNetwork(forceRouteRefresh: forceRouteRefresh) : nil
            let nextDisk: DiskStats? = includeDisk ? mon.sampleDisk() : nil
            let nextBat: BatteryStats? = includeBattery
                ? batSvc.sampleBattery(includeDetailedIORegistry: includeDetailedBattery, previous: prevBat)
                : nil
            let nextWiFi: WiFiState? = includeWiFi ? wifiSvc.sampleQuickState(previous: prevWiFi) : nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.isSamplingTelemetry = false
                if let nextCPU {
                    self.latestCPU = nextCPU
                }
                self.latestMemory = nextMem
                if let nextNet {
                    self.latestNetwork = nextNet
                }
                if let nextDisk {
                    self.latestDisk = nextDisk
                }
                if let nextBat {
                    self.latestBattery = includeDetailedBattery
                        ? nextBat
                        : mergeDetailedBatteryFields(from: self.latestBattery, into: nextBat)
                }
                if let nextWiFi {
                    self.latestWiFi = mergeWiFiLists(from: self.latestWiFi, into: nextWiFi)
                }

                // Only trigger SwiftUI @Published updates when popover or console window is actually visible
                if self.isUIActive || forcePublish {
                    self.publishLatestSnapshotsToUI()
                }
                self.onStatusBarNeedsRedraw?()

                if self.pendingHeavyRefresh || self.pendingForcePublish {
                    let heavy = self.pendingHeavyRefresh
                    let publish = self.pendingForcePublish
                    self.pendingHeavyRefresh = false
                    self.pendingForcePublish = false
                    if !self.isScreenAsleep {
                        self.refreshAll(includeHeavy: heavy, forcePublish: publish)
                    }
                }
            }
        }
    }

    public func onPopoverOpened() {
        isPopoverOpen = true
        publishLatestSnapshotsToUI()
        refreshAll(includeHeavy: true, forcePublish: true)
    }

    public func setConsoleOpen(_ open: Bool) {
        isConsoleOpen = open
        if open {
            publishLatestSnapshotsToUI()
            refreshAll(includeHeavy: true, forcePublish: true)
        }
    }

    // MARK: - On-Demand Process Telemetry

    public func refreshTopProcesses() {
        guard !isSamplingProcesses else { return }
        isSamplingProcesses = true
        if topCPUProcesses.isEmpty && topMemoryProcesses.isEmpty {
            isLoadingProcesses = true
        }
        let monitor = systemMonitor
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = monitor.sampleTopProcesses(limit: 6)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSamplingProcesses = false
                self.isLoadingProcesses = false
                if self.currentPage == .telemetry {
                    self.topCPUProcesses = result.topCPU
                    self.topMemoryProcesses = result.topMemory
                }
            }
        }
    }

    public func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - On-Demand Listening Port Radar

    public var parsedSearchedPort: Int? {
        let trimmed = portSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber),
              let p = Int(trimmed), (1...65535).contains(p) else {
            return nil
        }
        return p
    }

    public var filteredListeningPorts: [ListeningPortItem] {
        let q = portSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return listeningPorts }

        // If user entered a pure port number, prioritize exact port match first, then substring matches
        if let exactPort = parsedSearchedPort {
            let exact = listeningPorts.filter { $0.port == exactPort }
            if !exact.isEmpty {
                return exact
            }
            return listeningPorts.filter { String($0.port).contains(q) }
        }

        return listeningPorts.filter { item in
            String(item.port).contains(q)
                || item.processName.lowercased().contains(q)
                || item.bindAddress.lowercased().contains(q)
                || (item.pid.map(String.init)?.contains(q) ?? false)
                || (item.requiresSudo && ("root".contains(q) || "sudo".contains(q)))
        }
    }

    public func refreshListeningPorts() {
        guard !isSamplingPorts else { return }
        isSamplingPorts = true
        if listeningPorts.isEmpty {
            isLoadingPorts = true
        }
        let monitor = systemMonitor
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanned = monitor.sampleListeningPorts()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSamplingPorts = false
                self.isLoadingPorts = false
                guard self.isPopoverOpen, self.currentPage == .telemetry, self.telemetryTab == .ports else {
                    return
                }
                self.listeningPorts = scanned
                // Prune force-kill badges for PIDs that have exited
                let alivePIDs = Set(scanned.compactMap(\.pid))
                self.forceKillEligiblePIDs.formIntersection(alivePIDs)
            }
        }
    }

    /// Two-step confirmation to prevent accidental kills:
    /// First click arms confirmation for 3 seconds; second click sends SIGTERM (or SIGKILL if stubborn).
    public func requestOrConfirmKill(_ item: ListeningPortItem) {
        guard !item.requiresSudo, let pid = item.pid, !item.isSelfProcess else {
            copySudoCommand(item.sudoKillCommand, label: "已复制 sudo 终止命令")
            return
        }

        if pendingKillPortID != item.id {
            pendingKillPortID = item.id
            pendingKillResetWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    if self?.pendingKillPortID == item.id {
                        self?.pendingKillPortID = nil
                    }
                }
            }
            pendingKillResetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
            return
        }

        // Confirmed second click -> terminate
        pendingKillPortID = nil
        pendingKillResetWork?.cancel()

        let useForce = forceKillEligiblePIDs.contains(pid)
        let result = systemMonitor.terminateProcess(pid: pid, force: useForce)
        switch result {
        case .success:
            if !useForce {
                forceKillEligiblePIDs.insert(pid)
                showPortFeedback("已发送结束信号到 :\(item.port) (PID \(pid))")
            } else {
                showPortFeedback("已强制结束 :\(item.port) (PID \(pid))")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.refreshListeningPorts()
            }
        case .alreadyExited:
            showPortFeedback("端口 :\(item.port) 已释放")
            refreshListeningPorts()
        case .permissionDenied:
            copySudoCommand(item.sudoKillCommand, label: "权限不足，已自动复制 sudo 终止命令")
        case .protectedProcess:
            showPortFeedback("受保护进程，不允许结束")
        case .failed(let msg):
            showPortFeedback("结束失败：\(msg)")
        }
    }

    public func copySudoCommand(_ command: String, label: String = "已复制 sudo 命令") {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(command, forType: .string)
        showPortFeedback(label)
    }

    private func showPortFeedback(_ message: String) {
        portActionFeedback = message
        portFeedbackResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.portActionFeedback = nil
            }
        }
        portFeedbackResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    // MARK: - Wi-Fi Actions (In-Range Only)

    public func scanNearbyWiFi() {
        guard latestWiFi.isPoweredOn, !latestWiFi.isScanning else { return }
        latestWiFi.isScanning = true
        latestWiFi.lastError = nil
        if isUIActive {
            wifi = latestWiFi
        }
        let current = latestWiFi.currentSSID
        let rssi = latestWiFi.rssi
        wifiService.scanAndClassifyNetworks(
            currentSSID: current,
            currentRSSI: rssi
        ) { [weak self] knownNearby, otherNearby, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.latestWiFi.isScanning = false
                if self.latestWiFi.isPoweredOn {
                    self.latestWiFi.knownNetworks = knownNearby
                    self.latestWiFi.nearbyNetworks = otherNearby
                    if let error {
                        self.latestWiFi.lastError = error
                    }
                } else {
                    self.latestWiFi.knownNetworks = []
                    self.latestWiFi.nearbyNetworks = []
                }
                if self.isUIActive {
                    self.wifi = self.latestWiFi
                }
            }
        }
    }

    public func setWiFiPower(_ on: Bool) {
        let iface = latestWiFi.interfaceName
        latestWiFi.isPoweredOn = on
        latestWiFi.lastError = nil
        if !on {
            latestWiFi.isConnected = false
            latestWiFi.currentSSID = nil
            latestWiFi.knownNetworks = []
            latestWiFi.nearbyNetworks = []
            latestWiFi.isScanning = false
            latestWiFi.connectingSSID = nil
            passwordTargetSSID = nil
            passwordInput = ""
        }
        if isUIActive {
            wifi = latestWiFi
        }
        onStatusBarNeedsRedraw?()
        wifiService.setPower(on, interfaceName: iface) { [weak self] ok, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !ok {
                    self.latestWiFi.lastError = err ?? "无法切换 Wi-Fi 状态"
                    if self.isUIActive {
                        self.wifi = self.latestWiFi
                    }
                }
                self.refreshWiFiQuickState(throttled: false)
                if ok && on && self.isPopoverOpen && self.currentPage == .wifi {
                    self.scanNearbyWiFi()
                }
            }
        }
    }

    public func connectKnownWiFi(ssid: String) {
        guard latestWiFi.isPoweredOn, latestWiFi.connectingSSID == nil else { return }
        latestWiFi.connectingSSID = ssid
        latestWiFi.lastError = nil
        if isUIActive {
            wifi = latestWiFi
        }
        let iface = latestWiFi.interfaceName
        wifiService.connectToKnownNetwork(ssid: ssid, interfaceName: iface) { [weak self] ok, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.latestWiFi.connectingSSID = nil
                if !ok {
                    self.latestWiFi.lastError = err ?? "连接 \(ssid) 失败"
                }
                if self.isUIActive {
                    self.wifi = self.latestWiFi
                }
                self.refreshWiFiQuickState(throttled: false)
                if self.isPopoverOpen && self.currentPage == .wifi && self.latestWiFi.isPoweredOn {
                    self.scanNearbyWiFi()
                }
            }
        }
    }

    public func connectNearbyWiFi(ssid: String, password: String?) {
        guard latestWiFi.isPoweredOn, latestWiFi.connectingSSID == nil else { return }
        latestWiFi.connectingSSID = ssid
        latestWiFi.lastError = nil
        if isUIActive {
            wifi = latestWiFi
        }
        wifiService.connectToNearbyNetwork(ssid: ssid, password: password) { [weak self] ok, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.latestWiFi.connectingSSID = nil
                if !ok {
                    self.latestWiFi.lastError = err ?? "连接 \(ssid) 失败，请检查密码"
                }
                if self.isUIActive {
                    self.wifi = self.latestWiFi
                }
                self.refreshWiFiQuickState(throttled: false)
                if self.isPopoverOpen && self.currentPage == .wifi && self.latestWiFi.isPoweredOn {
                    self.scanNearbyWiFi()
                }
            }
        }
    }

    public func requestLocationForSSID() {
        wifiService.requestLocationPermission()
    }

    public func openWiFiSettings() {
        wifiService.openWiFiSettings()
    }

    // MARK: - Navigation & Battery

    public func navigate(to page: PopoverPage) {
        let wasTelemetry = (currentPage == .telemetry)
        let wasWiFi = (currentPage == .wifi)
        isGoingForward = (page != .overview)
        currentPage = page

        if wasWiFi && page != .wifi {
            passwordTargetSSID = nil
            passwordInput = ""
        }

        if page == .telemetry {
            refreshAll(includeHeavy: true, forcePublish: true)
            if telemetryTab == .ports {
                refreshListeningPorts()
            } else {
                refreshTopProcesses()
            }
        } else if wasTelemetry {
            systemMonitor.resetProcessSampler()
            pendingKillResetWork?.cancel()
            portFeedbackResetWork?.cancel()
            pendingKillPortID = nil
            portActionFeedback = nil
        }
    }

    public func resetNavigation() {
        isPopoverOpen = false
        if currentPage == .telemetry {
            systemMonitor.resetProcessSampler()
        }
        pendingKillResetWork?.cancel()
        portFeedbackResetWork?.cancel()
        isGoingForward = false
        currentPage = .overview
        showOtherNetworks = false
        passwordTargetSSID = nil
        passwordInput = ""
        portSearchQuery = ""
        pendingKillPortID = nil
        portActionFeedback = nil
    }

    public func toggleLowPowerMode() {
        guard !isTogglingLPM else { return }
        isTogglingLPM = true
        let next = !battery.isLowPowerMode
        batteryService.setLowPowerMode(enabled: next) { [weak self] ok in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isTogglingLPM = false
                if ok {
                    self.battery.isLowPowerMode = next
                    self.latestBattery.isLowPowerMode = next
                    self.onStatusBarNeedsRedraw?()
                }
                self.refreshBatteryState(throttled: false)
            }
        }
    }

    public func openBatterySettings() {
        batteryService.openBatterySettings()
    }

    // MARK: - Login Item

    public func refreshLaunchAtLoginState() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {}
        refreshLaunchAtLoginState()
    }
}

private func mergeWiFiLists(from current: WiFiState, into sampled: WiFiState) -> WiFiState {
    var merged = sampled
    if sampled.isPoweredOn {
        if !current.knownNetworks.isEmpty {
            merged.knownNetworks = current.knownNetworks
        }
        merged.nearbyNetworks = current.nearbyNetworks
    } else {
        merged.knownNetworks = []
        merged.nearbyNetworks = []
    }
    merged.isScanning = current.isScanning
    merged.connectingSSID = current.connectingSSID
    merged.lastError = current.lastError
    return merged
}

private func mergeDetailedBatteryFields(from current: BatteryStats, into sampled: BatteryStats) -> BatteryStats {
    var merged = sampled
    if current.cycleCount > 0 {
        merged.cycleCount = current.cycleCount
    }
    if current.healthPercent > 0 {
        merged.healthPercent = current.healthPercent
    }
    if sampled.isPluggedIn {
        if merged.adapterRatedWatts == nil {
            merged.adapterRatedWatts = current.adapterRatedWatts
        }
        if merged.systemPowerInWatts == nil {
            merged.systemPowerInWatts = current.systemPowerInWatts
        }
    } else {
        merged.adapterRatedWatts = nil
        merged.systemPowerInWatts = nil
    }
    if merged.systemLoadWatts == nil {
        merged.systemLoadWatts = current.systemLoadWatts
    }
    return merged
}

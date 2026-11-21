import Foundation
import Combine
import AppKit
import ServiceManagement

public enum PopoverPage: Equatable {
    case overview
    case wifi
    case battery
    case telemetry
    case audioBluetooth
    case display
    case keepAwake
    case scrollReverser
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
    @Published public var telemetryTab: TelemetrySortTab = .cpu
    @Published public var topCPUProcesses: [ProcessStatItem] = []
    @Published public var topMemoryProcesses: [ProcessStatItem] = []
    @Published public var isLoadingProcesses: Bool = false

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
    private var isSamplingProcesses = false
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
                self?.refreshBatteryState()
            }
        }

        wifiService.onWiFiEventChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshWiFiQuickState()
                if self.isPopoverOpen && self.currentPage == .wifi {
                    self.scanNearbyWiFi()
                }
            }
        }

        wifiService.onAuthorizationChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshWiFiQuickState()
                if self.isPopoverOpen && self.currentPage == .wifi {
                    self.scanNearbyWiFi()
                }
            }
        }

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
                }
            }
            workspaceObservers.append(obs)
        }

        for name in wakeNames {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isScreenAsleep = false
                    self.refreshAll(includeHeavy: true, forcePublish: self.isUIActive)
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
        let includeDisk = isUIActive && (tickCount % 15 == 0)
        let includeWiFiSignal = (tickCount % 3 == 0) || (isPopoverOpen && currentPage == .wifi)
        let includeBattery = isPopoverOpen && (currentPage == .battery)
        sampleTelemetryAsync(
            includeDisk: includeDisk,
            includeBattery: includeBattery,
            includeWiFi: includeWiFiSignal,
            forceRouteRefresh: false,
            forcePublish: false
        )
        if isPopoverOpen && currentPage == .telemetry {
            refreshTopProcesses()
        }
    }

    public func refreshAll(includeHeavy: Bool = false, forcePublish: Bool = false) {
        sampleTelemetryAsync(
            includeDisk: includeHeavy || latestDisk.totalGB == 0,
            includeBattery: true,
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

    private func refreshBatteryState() {
        let batSvc = batteryService
        telemetryQueue.async { [weak self] in
            let bat = batSvc.sampleBattery()
            DispatchQueue.main.async {
                guard let self else { return }
                self.latestBattery = bat
                if self.isUIActive {
                    self.battery = bat
                }
                self.onStatusBarNeedsRedraw?()
            }
        }
    }

    private func refreshWiFiQuickState() {
        let wifiSvc = wifiService
        let prevWiFi = latestWiFi
        let mon = systemMonitor
        telemetryQueue.async { [weak self] in
            let nextWiFi = wifiSvc.sampleQuickState(previous: prevWiFi)
            let nextNet = mon.sampleNetwork(forceRouteRefresh: true)
            DispatchQueue.main.async {
                guard let self else { return }
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
        includeDisk: Bool,
        includeBattery: Bool,
        includeWiFi: Bool,
        forceRouteRefresh: Bool,
        forcePublish: Bool
    ) {
        guard !isSamplingTelemetry else { return }
        isSamplingTelemetry = true

        let mon = systemMonitor
        let batSvc = batteryService
        let wifiSvc = wifiService
        let prevWiFi = latestWiFi

        telemetryQueue.async { [weak self] in
            let nextCPU = mon.sampleCPU()
            let nextMem = mon.sampleMemory()
            let nextNet = mon.sampleNetwork(forceRouteRefresh: forceRouteRefresh)
            let nextDisk: DiskStats? = includeDisk ? mon.sampleDisk() : nil
            let nextBat: BatteryStats? = includeBattery ? batSvc.sampleBattery() : nil
            let nextWiFi: WiFiState? = includeWiFi ? wifiSvc.sampleQuickState(previous: prevWiFi) : nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.isSamplingTelemetry = false
                self.latestCPU = nextCPU
                self.latestMemory = nextMem
                self.latestNetwork = nextNet
                if let nextDisk {
                    self.latestDisk = nextDisk
                }
                if let nextBat {
                    self.latestBattery = nextBat
                }
                if let nextWiFi {
                    self.latestWiFi = mergeWiFiLists(from: self.latestWiFi, into: nextWiFi)
                }

                // Only trigger SwiftUI @Published updates when popover or console window is actually visible
                if self.isUIActive || forcePublish {
                    self.publishLatestSnapshotsToUI()
                }
                self.onStatusBarNeedsRedraw?()
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

    // MARK: - Wi-Fi Actions (In-Range Only)

    public func scanNearbyWiFi() {
        guard wifi.isPoweredOn else { return }
        wifi.isScanning = true
        wifi.lastError = nil
        latestWiFi = wifi
        let current = wifi.currentSSID
        let rssi = wifi.rssi
        wifiService.scanAndClassifyNetworks(
            currentSSID: current,
            currentRSSI: rssi
        ) { [weak self] knownNearby, otherNearby, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wifi.isScanning = false
                self.wifi.knownNetworks = knownNearby
                self.wifi.nearbyNetworks = otherNearby
                if let error {
                    self.wifi.lastError = error
                }
                self.latestWiFi = self.wifi
            }
        }
    }

    public func setWiFiPower(_ on: Bool) {
        let iface = wifi.interfaceName
        wifi.isPoweredOn = on
        if !on {
            wifi.isConnected = false
            wifi.currentSSID = nil
            wifi.knownNetworks = []
            wifi.nearbyNetworks = []
        }
        latestWiFi = wifi
        onStatusBarNeedsRedraw?()
        wifiService.setPower(on, interfaceName: iface) { [weak self] ok, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !ok {
                    self.wifi.lastError = err ?? "无法切换 Wi-Fi 状态"
                    self.latestWiFi.lastError = self.wifi.lastError
                }
                self.refreshWiFiQuickState()
                if on && self.currentPage == .wifi {
                    self.scanNearbyWiFi()
                }
            }
        }
    }

    public func connectKnownWiFi(ssid: String) {
        guard wifi.isPoweredOn else { return }
        wifi.connectingSSID = ssid
        wifi.lastError = nil
        latestWiFi = wifi
        let iface = wifi.interfaceName
        wifiService.connectToKnownNetwork(ssid: ssid, interfaceName: iface) { [weak self] ok, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wifi.connectingSSID = nil
                if !ok {
                    self.wifi.lastError = err ?? "连接 \(ssid) 失败"
                }
                self.latestWiFi = self.wifi
                self.refreshWiFiQuickState()
                self.scanNearbyWiFi()
            }
        }
    }

    public func connectNearbyWiFi(ssid: String, password: String?) {
        guard wifi.isPoweredOn else { return }
        wifi.connectingSSID = ssid
        wifi.lastError = nil
        latestWiFi = wifi
        wifiService.connectToNearbyNetwork(ssid: ssid, password: password) { [weak self] ok, err in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wifi.connectingSSID = nil
                if !ok {
                    self.wifi.lastError = err ?? "连接 \(ssid) 失败，请检查密码"
                }
                self.latestWiFi = self.wifi
                self.refreshWiFiQuickState()
                self.scanNearbyWiFi()
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
        isGoingForward = (page != .overview)
        currentPage = page

        if page == .telemetry {
            refreshAll(includeHeavy: true, forcePublish: true)
            refreshTopProcesses()
        } else if wasTelemetry {
            systemMonitor.resetProcessSampler()
        }
    }

    public func resetNavigation() {
        isPopoverOpen = false
        if currentPage == .telemetry {
            systemMonitor.resetProcessSampler()
        }
        isGoingForward = false
        currentPage = .overview
        showOtherNetworks = false
        passwordTargetSSID = nil
        passwordInput = ""
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
                self.refreshBatteryState()
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
    if !current.knownNetworks.isEmpty && sampled.isPoweredOn {
        merged.knownNetworks = current.knownNetworks
    }
    merged.nearbyNetworks = sampled.isPoweredOn ? current.nearbyNetworks : []
    merged.isScanning = current.isScanning
    merged.connectingSSID = current.connectingSSID
    merged.lastError = current.lastError
    return merged
}

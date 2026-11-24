import AppKit
import Combine
import SwiftUI
import CoreKit
import DuoBarModule
import DisplayHiDPIModule
import KeepAwakeModule
import AudioBluetoothModule
import ScrollReverserModule
import ClipboardModule
import KeyboardLockModule
import SpaceCleanerModule

@main
struct YOMOLauncher {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private struct BadgeRenderKey: Equatable {
    let batteryPct: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isLPM: Bool
    let wifiOn: Bool
    let wifiBars: Int
    let topPctInt: Int
    let memoryPressure: MemoryStats.Pressure
    let cpuPctInt: Int
    let speedBucket: String
    let style: BadgeStyle
    let semanticColor: Bool
    let showBatteryPercentInRing: Bool
    let isDarkMenuBar: Bool
    let maxScaleBucket: Int
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let statusItemBaseAutosaveName = "YOMOStatusItem"
    private static let statusItemEpochDefaultsKey = "yomo.statusItemSlotEpoch"
    private var statusItem: NSStatusItem!
    private var statusItemGeneration: UInt64 = 0
    private var panel: GlassPopoverPanel!
    private var consoleWindow: NSWindow?
    private var consoleCloseObserver: NSObjectProtocol?

    private let moduleSettings = ModuleSettings()
    private let consoleViewModel = HubConsoleViewModel()
    private var duoBarStore: DuoBarStore!
    private var displayStore: DisplayHiDPIStore!
    private var keepAwakeStore: KeepAwakeStore!
    private var audioBluetoothStore: AudioBluetoothStore!
    private var scrollReverserStore: ScrollReverserStore!
    private var clipboardStore: ClipboardStore!
    private var keyboardLockStore: KeyboardLockStore!
    private var spaceCleanerStore: SpaceCleanerStore!

    private var eventMonitor: Any?
    private var lastRenderKey: BadgeRenderKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        duoBarStore = DuoBarStore()
        displayStore = DisplayHiDPIStore()
        keepAwakeStore = KeepAwakeStore()
        audioBluetoothStore = AudioBluetoothStore()
        scrollReverserStore = ScrollReverserStore()
        scrollReverserStore.syncWithModuleEnabled(moduleSettings.scrollReverserEnabled)
        clipboardStore = ClipboardStore()
        clipboardStore.onGlobalHotKeyPressed = { [weak self] in
            self?.toggleClipboardFromHotKey()
        }
        clipboardStore.syncWithModuleEnabled(moduleSettings.clipboardEnabled)
        keyboardLockStore = KeyboardLockStore()
        keyboardLockStore.syncWithModuleEnabled(moduleSettings.keyboardLockEnabled)
        spaceCleanerStore = SpaceCleanerStore()
        spaceCleanerStore.onSelfLoginItemChanged = { [weak self] in
            self?.duoBarStore.refreshLaunchAtLoginState()
        }

        // 1. Setup single Menu Bar Status Item (persisted autosaveName + optional right-edge priority)
        configureStatusItem(forceRightPosition: duoBarStore.prefs.pinStatusItemRight)

        // IMPORTANT: DO NOT observe `button.effectiveAppearance` via KVO.
        // On dual-display macOS 27, MenuBarAgent repeatedly flips effectiveAppearance across displays,
        // turning KVO -> redrawStatusBadge(force: true) into a 70%+ CPU infinite loop.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSystemThemeChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        // 2. Setup Borderless Native Liquid Glass Floating Panel
        let rootView = PopoverRootView(
            store: duoBarStore,
            moduleSettings: moduleSettings,
            displayStore: displayStore,
            keepAwakeStore: keepAwakeStore,
            audioBluetoothStore: audioBluetoothStore,
            scrollReverserStore: scrollReverserStore,
            clipboardStore: clipboardStore,
            keyboardLockStore: keyboardLockStore,
            spaceCleanerStore: spaceCleanerStore,
            onDismiss: { [weak self] in
                self?.panel.dismissAnimated()
            },
            onOpenConsole: { [weak self] target in
                self?.openHubConsole(sectionKey: target)
            },
            onQuit: { [weak self] in
                self?.keepAwakeStore.deactivate()
                self?.scrollReverserStore.deactivate(persistPreference: false)
                self?.clipboardStore.stop()
                self?.keyboardLockStore.unlock()
                self?.spaceCleanerStore.cancelScan()
                NSApp.terminate(nil)
            }
        )
        let glassPanel = GlassPopoverPanel(cardWidth: 316, rootView: rootView)
        glassPanel.applyAppearance(moduleSettings.glassAppearance)
        glassPanel.onClose = { [weak self] in
            self?.handlePanelClosed()
        }
        self.panel = glassPanel

        var lastAppliedAppearance = moduleSettings.glassAppearance
        moduleSettings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let current = self.moduleSettings.glassAppearance
                    guard current != lastAppliedAppearance else { return }
                    lastAppliedAppearance = current
                    self.panel.applyAppearance(current)
                }
            }
            .store(in: &cancellables)

        duoBarStore.onStatusBarNeedsRedraw = { [weak self] in
            self?.redrawStatusBadge()
        }
        duoBarStore.onStatusItemPositionRequested = { [weak self] in
            self?.configureStatusItem(forceRightPosition: true)
        }
        displayStore.onPerformDisplaySwitch = { [weak self] performSwitch in
            if let panel = self?.panel {
                panel.beginDisplayTransition(performSwitch: performSwitch)
            } else {
                performSwitch()
            }
        }

        redrawStatusBadge(force: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopOutsideClickMonitor()
        if let obs = consoleCloseObserver {
            NotificationCenter.default.removeObserver(obs)
            consoleCloseObserver = nil
        }
        DistributedNotificationCenter.default().removeObserver(self)
        keepAwakeStore?.deactivate()
        scrollReverserStore?.deactivate(persistPreference: false)
        clipboardStore?.stop()
        keyboardLockStore?.unlock()
        spaceCleanerStore?.cancelScan()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "YOMO")
        appMenu.addItem(withTitle: "退出 YOMO", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem(forceRightPosition: Bool) {
        statusItemGeneration &+= 1
        let gen = statusItemGeneration

        let hadExisting = (statusItem != nil)
        if let existing = statusItem {
            if panel?.isEffectivelyVisible == true {
                panel.dismissAnimated()
            }
            existing.autosaveName = nil
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }

        let createItem: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.statusItemGeneration == gen else { return }

            let defaults = UserDefaults.standard
            var epoch = max(1, defaults.integer(forKey: Self.statusItemEpochDefaultsKey))

            if forceRightPosition {
                // macOS MenuBarAgent caches manual ⌘-drag coordinates per (bundleID, autosaveName) inside its daemon.
                // Rotating to a fresh autosaveName epoch clears stale drag history so MenuBarAgent immediately honors
                // our 212pt preferred position (rightmost third-party slot, immediately left of Spotlight) without restart.
                defaults.removeObject(forKey: "NSStatusItem Preferred Position \(Self.statusItemBaseAutosaveName)")
                defaults.removeObject(forKey: "NSStatusItem Preferred Position \(Self.statusItemBaseAutosaveName)-\(epoch)")
                epoch += 1
                defaults.set(epoch, forKey: Self.statusItemEpochDefaultsKey)
            }

            let activeAutosaveName = "\(Self.statusItemBaseAutosaveName)-\(epoch)"
            if forceRightPosition {
                let targetOffset = 212.0
                defaults.set(targetOffset, forKey: "NSStatusItem Preferred Position \(activeAutosaveName)")
                defaults.set(targetOffset, forKey: "NSStatusItem Preferred Position Item-0")
                CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            }

            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = activeAutosaveName
            if let button = item.button {
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleNone
                button.target = self
                button.action = #selector(self.togglePanel(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.toolTip = "YOMO — You Only Menu Once"
            }
            self.statusItem = item
            self.lastRenderKey = nil
            self.redrawStatusBadge(force: true)
        }

        if hadExisting {
            // Yield briefly so MenuBarAgent finishes tearing down the old status item before creating the new epoch slot.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: createItem)
        } else {
            createItem()
        }
    }

    @objc private func handleSystemThemeChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.redrawStatusBadge(force: true)
        }
    }

    private func redrawStatusBadge(force: Bool = false) {
        guard let button = statusItem?.button else { return }
        let appearanceMatch = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let isDarkMenuBar = (appearanceMatch == .darkAqua)

        let bat = duoBarStore.latestBattery
        let wifi = duoBarStore.latestWiFi
        let cpu = duoBarStore.latestCPU
        let mem = duoBarStore.latestMemory
        let net = duoBarStore.latestNetwork

        let style = duoBarStore.prefs.badgeStyle
        let topPct = mem.usagePercent
        let showsCPUInBadge = (style == .dualRing || style == .triArc)
        let showsSpeedInBadge = (style == .capsule)
        let cpuKey = showsCPUInBadge ? (Int(round(cpu.totalUsage)) / 2) * 2 : 0
        let speedKey = showsSpeedInBadge ? net.dominantSpeedBucket : ""
        let maxScale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2.0

        let key = BadgeRenderKey(
            batteryPct: bat.percentage,
            isCharging: bat.isCharging,
            isPluggedIn: bat.isPluggedIn,
            isLPM: bat.isLowPowerMode,
            wifiOn: wifi.isPoweredOn,
            wifiBars: wifi.signalBars,
            topPctInt: Int(round(topPct)),
            memoryPressure: mem.pressureLevel,
            cpuPctInt: cpuKey,
            speedBucket: speedKey,
            style: style,
            semanticColor: duoBarStore.prefs.semanticColor,
            showBatteryPercentInRing: duoBarStore.prefs.showBatteryPercentInRing,
            isDarkMenuBar: isDarkMenuBar,
            maxScaleBucket: Int(round(maxScale * 100.0))
        )

        if !force && key == lastRenderKey {
            return
        }
        lastRenderKey = key

        let image = StatusBadgeRenderer.render(
            battery: bat,
            wifi: wifi,
            cpu: cpu,
            memory: mem,
            network: net,
            style: duoBarStore.prefs.badgeStyle,
            semanticColor: duoBarStore.prefs.semanticColor,
            showBatteryPercentInRing: duoBarStore.prefs.showBatteryPercentInRing,
            isDarkMenuBar: isDarkMenuBar
        )

        button.image = image
        let targetLength = image.size.width
        if abs(statusItem.length - targetLength) > 0.1 {
            statusItem.length = targetLength
        }
    }

    @objc private func togglePanel(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if panel.isEffectivelyVisible {
            panel.dismissAnimated()
        } else {
            duoBarStore.onPopoverOpened()
            keepAwakeStore.setUIActive(true)
            if moduleSettings.hidpiEnabled {
                displayStore.setUIActive(true)
                displayStore.refreshDisplays()
            }
            if moduleSettings.audioBluetoothEnabled {
                audioBluetoothStore.setUIActive(true)
                audioBluetoothStore.refreshAudioDevices()
                audioBluetoothStore.refreshBluetoothDevices()
            }
            if moduleSettings.scrollReverserEnabled {
                scrollReverserStore.refreshPermissionState()
            }
            if moduleSettings.clipboardEnabled {
                clipboardStore.setUIActive(true)
            }
            if moduleSettings.keyboardLockEnabled {
                keyboardLockStore.refreshPermissionState()
            }
            button.highlight(true)
            panel.show(relativeTo: button)
            startOutsideClickMonitor()
        }
    }

    private func toggleClipboardFromHotKey() {
        guard moduleSettings.clipboardEnabled, let button = statusItem.button else { return }

        if panel.isEffectivelyVisible && duoBarStore.currentPage == .clipboard {
            panel.dismissAnimated()
            return
        }

        duoBarStore.onPopoverOpened()
        keepAwakeStore.setUIActive(true)
        audioBluetoothStore.setUIActive(true)
        clipboardStore.setUIActive(true)

        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            duoBarStore.navigate(to: .clipboard)
        }
        panel.contentView?.layoutSubtreeIfNeeded()

        if !panel.isEffectivelyVisible {
            button.highlight(true)
            panel.show(relativeTo: button)
            startOutsideClickMonitor()
        }
    }

    private func handlePanelClosed() {
        statusItem.button?.highlight(false)
        stopOutsideClickMonitor()
        duoBarStore.resetNavigation()
        moduleSettings.isEditingOverviewLayout = false
        clipboardStore.searchQuery = ""
        let consoleVisible = (consoleWindow?.isVisible == true)
        clipboardStore.setUIActive(consoleVisible)
        displayStore.setUIActive(consoleVisible)
        keepAwakeStore.setUIActive(consoleVisible)
        audioBluetoothStore.setUIActive(consoleVisible)
    }

    private func openHubConsole(sectionKey: String?) {
        if panel.isEffectivelyVisible {
            panel.dismissAnimated()
        }
        if let key = sectionKey, let sec = ConsoleSection(rawValue: key) {
            consoleViewModel.selectedSection = sec
        } else {
            consoleViewModel.selectedSection = .dashboard
        }

        if consoleWindow == nil {
            let contentView = HubConsoleView(
                viewModel: consoleViewModel,
                moduleSettings: moduleSettings,
                duoBarStore: duoBarStore,
                displayStore: displayStore,
                keepAwakeStore: keepAwakeStore,
                audioBluetoothStore: audioBluetoothStore,
                scrollReverserStore: scrollReverserStore,
                clipboardStore: clipboardStore,
                keyboardLockStore: keyboardLockStore,
                spaceCleanerStore: spaceCleanerStore
            )
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            // Empty unified toolbar shifts macOS traffic lights inward to the modern inset position (~20pt)
            // so they sit cleanly inside the floating white sidebar card instead of crowding the corner.
            let toolbar = NSToolbar(identifier: "YOMOConsoleToolbar")
            toolbar.showsBaselineSeparator = false
            win.toolbar = toolbar
            win.toolbarStyle = .unified
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.titlebarSeparatorStyle = .none
            win.isMovableByWindowBackground = true
            win.minSize = NSSize(width: 720, height: 480)
            win.title = "YOMO 控制台"
            win.isReleasedWhenClosed = false
            win.contentViewController = NSHostingController(rootView: contentView)
            win.center()
            if let oldObs = consoleCloseObserver {
                NotificationCenter.default.removeObserver(oldObs)
                consoleCloseObserver = nil
            }
            consoleCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.duoBarStore.setConsoleOpen(false)
                    let popoverVisible = self.panel.isEffectivelyVisible
                    self.clipboardStore.setUIActive(popoverVisible)
                    self.displayStore.setUIActive(popoverVisible)
                    self.keepAwakeStore.setUIActive(popoverVisible)
                    self.audioBluetoothStore.setUIActive(popoverVisible)
                    if let obs = self.consoleCloseObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self.consoleCloseObserver = nil
                    }
                    self.consoleWindow?.contentViewController = nil
                    self.consoleWindow = nil
                }
            }
            consoleWindow = win
        }

        duoBarStore.setConsoleOpen(true)
        clipboardStore.setUIActive(true)
        displayStore.setUIActive(true)
        keepAwakeStore.setUIActive(true)
        audioBluetoothStore.setUIActive(true)
        NSApp.activate()
        consoleWindow?.makeKeyAndOrderFront(nil)
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                if self?.panel.isEffectivelyVisible == true {
                    self?.panel.dismissAnimated()
                }
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

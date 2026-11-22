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
    private var statusItem: NSStatusItem!
    private var panel: GlassPopoverPanel!
    private var consoleWindow: NSWindow?

    private let moduleSettings = ModuleSettings()
    private let consoleViewModel = HubConsoleViewModel()
    private var duoBarStore: DuoBarStore!
    private var displayStore: DisplayHiDPIStore!
    private var keepAwakeStore: KeepAwakeStore!
    private var audioBluetoothStore: AudioBluetoothStore!
    private var scrollReverserStore: ScrollReverserStore!
    private var clipboardStore: ClipboardStore!
    private var keyboardLockStore: KeyboardLockStore!

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

        // 1. Setup single Menu Bar Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "YOMO — You Only Menu Once"
        }

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
        var panelRef: GlassPopoverPanel?
        let rootView = PopoverRootView(
            store: duoBarStore,
            moduleSettings: moduleSettings,
            displayStore: displayStore,
            keepAwakeStore: keepAwakeStore,
            audioBluetoothStore: audioBluetoothStore,
            scrollReverserStore: scrollReverserStore,
            clipboardStore: clipboardStore,
            keyboardLockStore: keyboardLockStore,
            onDismiss: {
                panelRef?.dismissAnimated()
            },
            onOpenConsole: { [weak self] target in
                self?.openHubConsole(sectionKey: target)
            },
            onQuit: { [weak self] in
                self?.keepAwakeStore.deactivate()
                self?.scrollReverserStore.deactivate(persistPreference: false)
                self?.clipboardStore.stop()
                self?.keyboardLockStore.unlock()
                NSApp.terminate(nil)
            }
        )
        let glassPanel = GlassPopoverPanel(cardWidth: 316, rootView: rootView)
        glassPanel.applyAppearance(moduleSettings.glassAppearance)
        panelRef = glassPanel
        glassPanel.onClose = { [weak self] in
            self?.handlePanelClosed()
        }
        self.panel = glassPanel

        moduleSettings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.panel.applyAppearance(self.moduleSettings.glassAppearance)
                }
            }
            .store(in: &cancellables)

        duoBarStore.onStatusBarNeedsRedraw = { [weak self] in
            self?.redrawStatusBadge()
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
        DistributedNotificationCenter.default().removeObserver(self)
        keepAwakeStore?.deactivate()
        scrollReverserStore?.deactivate(persistPreference: false)
        clipboardStore?.stop()
        keyboardLockStore?.unlock()
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

        let topPct = mem.usagePercent
        let speedBucket = net.dominantSpeedBucket
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
            cpuPctInt: Int(round(cpu.totalUsage)),
            speedBucket: speedBucket,
            style: duoBarStore.prefs.badgeStyle,
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

        if panel.isVisible {
            panel.dismissAnimated()
        } else {
            duoBarStore.onPopoverOpened()
            if moduleSettings.hidpiEnabled {
                displayStore.setUIActive(true)
                displayStore.refreshDisplays()
            }
            if moduleSettings.audioBluetoothEnabled {
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

        if panel.isVisible && duoBarStore.currentPage == .clipboard {
            panel.dismissAnimated()
            return
        }

        duoBarStore.onPopoverOpened()
        clipboardStore.setUIActive(true)
        duoBarStore.navigate(to: .clipboard)

        if !panel.isVisible {
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
        moduleSettings.draggingOverviewTile = nil
        moduleSettings.dragTranslation = .zero
        clipboardStore.searchQuery = ""
        let consoleVisible = (consoleWindow?.isVisible == true)
        clipboardStore.setUIActive(consoleVisible)
        displayStore.setUIActive(consoleVisible)
    }

    private func openHubConsole(sectionKey: String?) {
        if panel.isVisible {
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
                keyboardLockStore: keyboardLockStore
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
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: win,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.duoBarStore.setConsoleOpen(false)
                    let popoverVisible = (self?.panel.isVisible == true)
                    self?.clipboardStore.setUIActive(popoverVisible)
                    self?.displayStore.setUIActive(popoverVisible)
                }
            }
            consoleWindow = win
        }

        duoBarStore.setConsoleOpen(true)
        clipboardStore.setUIActive(true)
        displayStore.setUIActive(true)
        NSApp.activate()
        consoleWindow?.makeKeyAndOrderFront(nil)
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                if self?.panel.isVisible == true {
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

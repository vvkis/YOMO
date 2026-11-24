import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

private struct ScrollTapConfig {
    var reverseVertical: Bool
    var reverseHorizontal: Bool
    var mouseOnly: Bool
}

/// Low-level Quartz CGEventTap engine for reversing discrete mouse scroll wheels
/// while preserving macOS Trackpad natural scrolling.
/// Zero allocations inside the C callback; completely torn down when inactive (0.0% idle CPU).
private final class ScrollEventTapEngine {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var config: ScrollTapConfig

    var isRunning: Bool { eventTap != nil }

    init(config: ScrollTapConfig) {
        self.config = config
    }

    deinit {
        stop()
    }

    func updateConfig(_ newConfig: ScrollTapConfig) {
        config = newConfig
    }

    func start() -> Bool {
        if eventTap != nil { return true }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let engine = Unmanaged<ScrollEventTapEngine>.fromOpaque(refcon).takeUnretainedValue()
                return engine.handleEvent(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        let cfg = config

        // scrollWheelEventIsContinuous: 0 = discrete stepped mouse wheel, 1 = trackpad / Magic Mouse gesture
        if cfg.mouseOnly {
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            if isContinuous != 0 {
                return Unmanaged.passUnretained(event)
            }
        }

        if cfg.reverseVertical {
            // Read all three representations BEFORE writing, because setting DeltaAxis1
            // automatically recalculates/overwrites PointDeltaAxis1 and FixedPtDeltaAxis1.
            let line1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let fixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)

            if line1 != 0 || point1 != 0 || fixed1 != 0 {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -line1)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -point1)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixed1)
            }
        }

        if cfg.reverseHorizontal {
            let line2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let point2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let fixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

            if line2 != 0 || point2 != 0 || fixed2 != 0 {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -line2)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -point2)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixed2)
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

@MainActor
public final class ScrollReverserStore: ObservableObject {
    private enum Keys {
        static let desiredEnabled = "scrollReverser.desiredEnabled"
        static let reverseVertical = "scrollReverser.reverseVertical"
        static let reverseHorizontal = "scrollReverser.reverseHorizontal"
        static let mouseOnly = "scrollReverser.mouseOnly"
    }

    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var hasAccessibilityPermission: Bool = false
    @Published public var statusMessage: String? = nil

    @Published public var reverseVertical: Bool {
        didSet {
            UserDefaults.standard.set(reverseVertical, forKey: Keys.reverseVertical)
            syncEngineConfig()
        }
    }

    @Published public var reverseHorizontal: Bool {
        didSet {
            UserDefaults.standard.set(reverseHorizontal, forKey: Keys.reverseHorizontal)
            syncEngineConfig()
        }
    }

    @Published public var mouseOnly: Bool {
        didSet {
            UserDefaults.standard.set(mouseOnly, forKey: Keys.mouseOnly)
            syncEngineConfig()
        }
    }

    private var desiredEnabled: Bool
    private var moduleEnabled: Bool = true
    private let engine: ScrollEventTapEngine
    private var activeObserver: NSObjectProtocol?

    public init() {
        let ud = UserDefaults.standard
        let revV = ud.object(forKey: Keys.reverseVertical) as? Bool ?? true
        let revH = ud.object(forKey: Keys.reverseHorizontal) as? Bool ?? false
        let mOnly = ud.object(forKey: Keys.mouseOnly) as? Bool ?? true
        let desired = ud.object(forKey: Keys.desiredEnabled) as? Bool ?? false

        self.reverseVertical = revV
        self.reverseHorizontal = revH
        self.mouseOnly = mOnly
        self.desiredEnabled = desired
        self.engine = ScrollEventTapEngine(
            config: ScrollTapConfig(reverseVertical: revV, reverseHorizontal: revH, mouseOnly: mOnly)
        )
        self.hasAccessibilityPermission = AXIsProcessTrusted()

        // Event-driven permission refresh when user returns from System Settings (zero background polling)
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionState()
            }
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        engine.stop()
    }

    /// Called at launch or when the user toggles the module master switch in Console.
    public func syncWithModuleEnabled(_ enabled: Bool) {
        moduleEnabled = enabled
        if !enabled {
            deactivate(persistPreference: false)
        } else {
            refreshPermissionState()
        }
    }

    public func refreshPermissionState() {
        let trusted = AXIsProcessTrusted()
        hasAccessibilityPermission = trusted

        if trusted {
            if desiredEnabled && moduleEnabled && !isActive {
                _ = startTapInternal()
            } else if statusMessage != nil {
                statusMessage = nil
            }
        } else if isActive {
            engine.stop()
            isActive = false
            statusMessage = "辅助功能权限已撤销，滚轮翻转已暂停"
        }
    }

    public func toggle() {
        setEnabled(!isActive)
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled {
            desiredEnabled = true
            UserDefaults.standard.set(true, forKey: Keys.desiredEnabled)

            let trusted = AXIsProcessTrusted()
            hasAccessibilityPermission = trusted
            guard trusted else {
                isActive = false
                statusMessage = "请先在「隐私与安全性 → 辅助功能」中允许 YOMO"
                requestAccessibilityPermission()
                return
            }

            if !startTapInternal() {
                statusMessage = "无法创建事件监听，请确认辅助功能权限已生效"
            }
        } else {
            deactivate(persistPreference: true)
        }
    }

    public func deactivate(persistPreference: Bool = false) {
        if persistPreference {
            desiredEnabled = false
            UserDefaults.standard.set(false, forKey: Keys.desiredEnabled)
        }
        engine.stop()
        isActive = false
        statusMessage = nil
    }

    public func requestAccessibilityPermission() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: kCFBooleanTrue as Any] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = trusted
        if trusted && desiredEnabled && moduleEnabled {
            _ = startTapInternal()
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public var statusSubtitle: String {
        if isActive {
            let scope = mouseOnly ? "鼠标" : "全局"
            switch (reverseVertical, reverseHorizontal) {
            case (true, true):
                return "已开启 · \(scope)垂直+水平"
            case (true, false):
                return mouseOnly ? "已开启 · 仅鼠标滚轮" : "已开启 · 全局垂直"
            case (false, true):
                return "已开启 · \(scope)仅水平"
            case (false, false):
                return "已开启 · 未勾选方向"
            }
        }
        if !hasAccessibilityPermission && desiredEnabled {
            return "等待辅助功能授权"
        }
        return "已关闭"
    }

    private func startTapInternal() -> Bool {
        syncEngineConfig()
        let started = engine.start()
        isActive = started
        if started {
            statusMessage = nil
        }
        return started
    }

    private func syncEngineConfig() {
        engine.updateConfig(
            ScrollTapConfig(
                reverseVertical: reverseVertical,
                reverseHorizontal: reverseHorizontal,
                mouseOnly: mouseOnly
            )
        )
    }
}

import Foundation
import AppKit
import SwiftUI
import Carbon
import CoreGraphics
import ApplicationServices
import CoreKit

/// Low-level Quartz CGEventTap engine that swallows keyboard & media-key input while cleaning.
/// Runs on the main run loop; completely torn down when unlocked (0.0% idle CPU).
private final class KeyboardLockTapEngine {
    private static let systemDefinedEventRawValue: UInt32 = 14 // NX_SYSDEFINED (brightness, volume, media keys)
    private static let auxControlSubtype: Int16 = 8            // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onBlockedKeystroke: () -> Void
    private let onEmergencyUnlock: () -> Void

    var isRunning: Bool { eventTap != nil }

    init(
        onBlockedKeystroke: @escaping () -> Void,
        onEmergencyUnlock: @escaping () -> Void
    ) {
        self.onBlockedKeystroke = onBlockedKeystroke
        self.onEmergencyUnlock = onEmergencyUnlock
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        if eventTap != nil { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << Self.systemDefinedEventRawValue)

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
                let engine = Unmanaged<KeyboardLockTapEngine>.fromOpaque(refcon).takeUnretainedValue()
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

        switch type {
        case .keyDown:
            // Emergency escape chord: Control + Option + Command + U
            let flags = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let hasEmergencyModifiers =
                flags.contains(.maskControl) &&
                flags.contains(.maskAlternate) &&
                flags.contains(.maskCommand)
            if hasEmergencyModifiers && keyCode == Int64(kVK_ANSI_U) {
                DispatchQueue.main.async { [onEmergencyUnlock] in
                    onEmergencyUnlock()
                }
                return nil
            }
            onBlockedKeystroke()
            return nil

        case .keyUp, .flagsChanged:
            return nil

        default:
            // Swallow macOS top-row media / brightness / volume / mute keys (NX_SYSDEFINED subtype 8)
            if type.rawValue == Self.systemDefinedEventRawValue,
               let nsEvent = NSEvent(cgEvent: event),
               nsEvent.subtype.rawValue == Self.auxControlSubtype {
                // Only count key-down half (bits 8..11 == 0x0A) so counter increments once per press
                let keyState = (nsEvent.data1 & 0x0000FF00) >> 8
                if keyState == 0x0A {
                    onBlockedKeystroke()
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
    }
}

/// Sleek floating Liquid Glass pill shown while Keyboard Lock is active so the user can always
/// see lock status at a glance and unlock with one click of the mouse/trackpad.
@MainActor
private final class KeyboardLockHUDPanel: NSPanel {
    private let panelWidth: CGFloat = 312
    private let panelHeight: CGFloat = 62
    private var animationGeneration: UInt64 = 0

    init(store: KeyboardLockStore) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true

        let host = NSHostingView(rootView: KeyboardLockHUDView(store: store))
        host.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        host.autoresizingMask = [.width, .height]
        self.contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showCenteredNearBottom() {
        animationGeneration &+= 1
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        if let screen = targetScreen {
            let vf = screen.visibleFrame
            let x = round(vf.midX - panelWidth / 2.0)
            let y = round(vf.minY + 46.0)
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
        }
    }

    func hideSmoothly(onHidden: (@MainActor () -> Void)? = nil) {
        animationGeneration &+= 1
        let gen = animationGeneration
        guard isVisible else {
            onHidden?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.animationGeneration == gen else { return }
                self.orderOut(nil)
                self.alphaValue = 1.0
                onHidden?()
            }
        })
    }
}

private struct KeyboardLockHUDView: View {
    @ObservedObject var store: KeyboardLockStore

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.22))
                    .frame(width: 34, height: 34)
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("键盘已锁定 · 清洁模式")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(store.blockedCount > 0 ? "已拦截 \(store.blockedCount) 次按键 · ⌃⌥⌘U 可解锁" : "鼠标可用 · ⌃⌥⌘U 也可解锁")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                store.unlock()
            } label: {
                Text("解锁")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)
            .help("立即解锁键盘")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule()
                .fill(Color(nsColor: NSColor(white: 0.11, alpha: 0.90)))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                )
        )
    }
}

@MainActor
public final class KeyboardLockStore: ObservableObject {
    @Published public private(set) var isLocked: Bool = false
    @Published public private(set) var blockedCount: Int = 0
    @Published public private(set) var hasAccessibilityPermission: Bool = false
    @Published public var statusMessage: String? = nil

    private var engine: KeyboardLockTapEngine?
    private var hudPanel: KeyboardLockHUDPanel?
    private var sleepObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    public init() {
        self.hasAccessibilityPermission = AXIsProcessTrusted()
        self.engine = KeyboardLockTapEngine(
            onBlockedKeystroke: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isLocked else { return }
                    self.blockedCount += 1
                }
            },
            onEmergencyUnlock: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.unlock()
                }
            }
        )

        // Never leave the keyboard locked across system sleep
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.unlock()
            }
        }

        // Auto-refresh Accessibility status when returning from System Settings
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
        engine?.stop()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    public var statusSubtitle: String {
        if isLocked {
            return blockedCount > 0 ? "已锁定 · 已拦截 \(blockedCount) 次" : "已锁定 · 清洁中"
        }
        return hasAccessibilityPermission ? "点击即锁 · 清理键盘防误触" : "需要辅助功能权限"
    }

    public func refreshPermissionState() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        if !hasAccessibilityPermission {
            if isLocked {
                unlock()
            }
        } else {
            if statusMessage != nil {
                statusMessage = nil
            }
            if isLocked && !(engine?.isRunning ?? false) {
                unlock()
            }
        }
    }

    public func syncWithModuleEnabled(_ enabled: Bool) {
        if !enabled {
            unlock()
        }
    }

    /// Toggles keyboard lock state. Returns `true` if the action succeeded, or `false` if Accessibility permission is missing.
    @discardableResult
    public func toggle() -> Bool {
        if isLocked {
            unlock()
            return true
        } else {
            return lock()
        }
    }

    /// Locks keyboard input (including media/function keys). Commits `isLocked = true` ONLY after CGEventTap succeeds.
    @discardableResult
    public func lock() -> Bool {
        if isLocked { return true }
        hasAccessibilityPermission = AXIsProcessTrusted()
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            statusMessage = "请先在「系统设置 → 隐私与安全性 → 辅助功能」中授权 YOMO"
            return false
        }

        guard engine?.start() == true else {
            hasAccessibilityPermission = AXIsProcessTrusted()
            statusMessage = "键盘事件拦截启动失败，请检查辅助功能权限"
            return false
        }

        blockedCount = 0
        isLocked = true
        statusMessage = nil

        if hudPanel == nil {
            hudPanel = KeyboardLockHUDPanel(store: self)
        }
        hudPanel?.showCenteredNearBottom()
        return true
    }

    public func unlock() {
        engine?.stop()
        if isLocked {
            isLocked = false
        }
        hudPanel?.hideSmoothly { [weak self] in
            guard let self, !self.isLocked else { return }
            self.hudPanel?.contentView = nil
            self.hudPanel = nil
        }
    }

    public func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

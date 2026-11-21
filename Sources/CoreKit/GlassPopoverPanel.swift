import AppKit
import SwiftUI

@MainActor
public final class GlassPopoverPanel: NSPanel {
    private let cardWidth: CGFloat
    private let horizontalPadding: CGFloat = 20
    private let canvasHeight: CGFloat = 600
    private weak var anchorButton: NSStatusBarButton?
    private var screenObserver: NSObjectProtocol?
    private var isInDisplayTransition = false
    private var transitionWorkItem: DispatchWorkItem?
    public var onClose: (() -> Void)?

    public init<Content: View>(cardWidth: CGFloat = 316, rootView: Content) {
        self.cardWidth = cardWidth
        let canvasWidth = cardWidth + horizontalPadding * 2
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: canvasWidth, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // Disable macOS's built-in rectangular/default window shadow & corner mask;
        // the Liquid Glass card inside SwiftUI renders its own crisp 24pt shadow.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none

        let host = NSHostingView(rootView: AnyView(rootView))
        host.frame = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = host

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenParametersChanged()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    public func applyAppearance(_ mode: GlassAppearanceMode) {
        switch mode {
        case .dark:
            self.appearance = NSAppearance(named: .darkAqua)
        case .light:
            self.appearance = NSAppearance(named: .aqua)
        case .auto:
            self.appearance = nil
        }
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func cancelOperation(_ sender: Any?) {
        dismissAnimated()
    }

    public override func resignKey() {
        super.resignKey()
        if isVisible && !isInDisplayTransition {
            dismissAnimated()
        }
    }

    /// Closes the floating panel and flushes the hide commit to WindowServer BEFORE running
    /// the synchronous display mode switch, so the panel never lingers/ghosts during reconfiguration.
    public func beginDisplayTransition(performSwitch: @escaping @MainActor () -> Void) {
        guard isVisible else {
            performSwitch()
            return
        }
        isInDisplayTransition = true
        transitionWorkItem?.cancel()

        // Hide immediately and force CoreAnimation/WindowServer to commit removal before mode switch blocks main thread
        alphaValue = 0
        orderOut(nil)
        CATransaction.flush()

        // Safety fallback in case the display switch doesn't emit screen-param change
        let fallback = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishDisplayTransition()
            }
        }
        transitionWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70, execute: fallback)

        // Wait ~2 frames (~35ms) so WindowServer finishes compositing the hidden state before changing resolution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
            Task { @MainActor in
                performSwitch()
            }
        }
    }

    private func handleScreenParametersChanged() {
        guard let button = anchorButton else { return }

        if isInDisplayTransition {
            // Wait briefly for NSStatusBar / MenuBarAgent to settle its button position on the new resolution,
            // then reopen cleanly right under the menu bar icon on the same HiDPI page.
            transitionWorkItem?.cancel()
            let reveal = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finishDisplayTransition()
                }
            }
            transitionWorkItem = reveal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: reveal)
        } else if isVisible {
            // External resolution change while open: unconditionally re-anchor under status bar button
            let targetFrame = computeFrame(button: button)
            setFrame(targetFrame, display: true, animate: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                guard let self, self.isVisible, let btn = self.anchorButton else { return }
                self.setFrame(self.computeFrame(button: btn), display: true, animate: false)
            }
        }
    }

    private func finishDisplayTransition() {
        transitionWorkItem?.cancel()
        transitionWorkItem = nil
        guard isInDisplayTransition, let button = anchorButton else {
            isInDisplayTransition = false
            return
        }

        let targetFrame = computeFrame(button: button)
        var startFrame = targetFrame
        startFrame.origin.y += 5
        setFrame(startFrame, display: false)
        alphaValue = 0

        NSApp.activate()
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
            animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.isInDisplayTransition = false
            }
        })
    }

    public func show(relativeTo button: NSStatusBarButton) {
        isInDisplayTransition = false
        transitionWorkItem?.cancel()
        anchorButton = button
        let targetFrame = computeFrame(button: button)

        var startFrame = targetFrame
        startFrame.origin.y += 6
        setFrame(startFrame, display: false)
        alphaValue = 0

        NSApp.activate()
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
            animator().setFrame(targetFrame, display: true)
        }
    }

    public func dismissAnimated() {
        guard isVisible else { return }
        isInDisplayTransition = false
        transitionWorkItem?.cancel()
        var endFrame = frame
        endFrame.origin.y += 4
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0.0
            animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.anchorButton = nil
                self?.orderOut(nil)
                self?.alphaValue = 1.0
                self?.onClose?()
            }
        })
    }

    private func computeFrame(button: NSStatusBarButton) -> NSRect {
        let canvasWidth = cardWidth + horizontalPadding * 2
        guard let buttonWindow = button.window else {
            return NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame

        // Align visible glass card neatly under the status bar item, clamped within screen bounds
        let margin: CGFloat = 8
        var cardX = buttonScreenRect.midX - cardWidth / 2.0
        cardX = min(cardX, visibleFrame.maxX - cardWidth - margin)
        cardX = max(cardX, visibleFrame.minX + margin)

        let canvasX = cardX - horizontalPadding
        let clampedHeight = min(canvasHeight, max(240, visibleFrame.height - 8))
        let topY = buttonScreenRect.minY
        let canvasY = topY - clampedHeight

        return NSRect(x: round(canvasX), y: round(canvasY), width: canvasWidth, height: clampedHeight)
    }
}

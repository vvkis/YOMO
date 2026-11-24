import SwiftUI
import CoreKit
import DisplayHiDPIModule
import KeepAwakeModule
import AudioBluetoothModule
import ScrollReverserModule
import ClipboardModule
import KeyboardLockModule
import SpaceCleanerModule

public struct PopoverRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject public var store: DuoBarStore
    public let moduleSettings: ModuleSettings
    public let displayStore: DisplayHiDPIStore
    public let keepAwakeStore: KeepAwakeStore
    public let audioBluetoothStore: AudioBluetoothStore
    public let scrollReverserStore: ScrollReverserStore
    public let clipboardStore: ClipboardStore
    public let keyboardLockStore: KeyboardLockStore
    public let spaceCleanerStore: SpaceCleanerStore
    public let onDismiss: () -> Void
    public let onOpenConsole: (String?) -> Void
    public let onQuit: () -> Void

    public init(
        store: DuoBarStore,
        moduleSettings: ModuleSettings,
        displayStore: DisplayHiDPIStore,
        keepAwakeStore: KeepAwakeStore,
        audioBluetoothStore: AudioBluetoothStore,
        scrollReverserStore: ScrollReverserStore,
        clipboardStore: ClipboardStore,
        keyboardLockStore: KeyboardLockStore,
        spaceCleanerStore: SpaceCleanerStore,
        onDismiss: @escaping () -> Void,
        onOpenConsole: @escaping (String?) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.store = store
        self.moduleSettings = moduleSettings
        self.displayStore = displayStore
        self.keepAwakeStore = keepAwakeStore
        self.audioBluetoothStore = audioBluetoothStore
        self.scrollReverserStore = scrollReverserStore
        self.clipboardStore = clipboardStore
        self.keyboardLockStore = keyboardLockStore
        self.spaceCleanerStore = spaceCleanerStore
        self.onDismiss = onDismiss
        self.onOpenConsole = onOpenConsole
        self.onQuit = onQuit
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)

        ZStack(alignment: .top) {
            // Transparent outer backdrop catcher so clicking outside the glass card dismisses cleanly
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }

            // Floating Liquid Glass Card (single unified spring curve for height morph + page transition)
            ZStack(alignment: .top) {
                // Absorbs clicks on empty card padding without ever intercepting child buttons/gestures
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}

                switch store.currentPage {
                case .overview:
                    OverviewView(
                        store: store,
                        moduleSettings: moduleSettings,
                        displayStore: displayStore,
                        keepAwakeStore: keepAwakeStore,
                        audioBluetoothStore: audioBluetoothStore,
                        scrollReverserStore: scrollReverserStore,
                        clipboardStore: clipboardStore,
                        keyboardLockStore: keyboardLockStore,
                        spaceCleanerStore: spaceCleanerStore,
                        onNavigate: { target in
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                store.navigate(to: target)
                            }
                        },
                        onDismiss: onDismiss,
                        onOpenConsole: onOpenConsole,
                        onQuit: onQuit
                    )
                    .transition(pageTransition)

                case .wifi:
                    WiFiDetailView(store: store, onBack: goBack)
                        .transition(pageTransition)

                case .battery:
                    BatteryDetailView(store: store, onBack: goBack)
                        .transition(pageTransition)

                case .telemetry:
                    SystemTelemetryDetailView(store: store, onBack: goBack)
                        .transition(pageTransition)

                case .audioBluetooth:
                    AudioBluetoothPopoverView(store: audioBluetoothStore, onBack: goBack)
                        .transition(pageTransition)

                case .display:
                    DisplayHiDPIPopoverView(
                        store: displayStore,
                        onBack: goBack,
                        onOpenConsole: { onOpenConsole("hidpi") }
                    )
                    .transition(pageTransition)

                case .keepAwake:
                    KeepAwakePopoverView(store: keepAwakeStore, onBack: goBack)
                        .transition(pageTransition)

                case .scrollReverser:
                    ScrollReverserPopoverView(store: scrollReverserStore, onBack: goBack)
                        .transition(pageTransition)

                case .clipboard:
                    ClipboardPopoverView(
                        store: clipboardStore,
                        onBack: goBack,
                        onItemCopied: onDismiss,
                        onOpenConsole: { onOpenConsole("clipboard") }
                    )
                    .transition(pageTransition)

                case .spaceCleaner:
                    SpaceCleanerPopoverView(
                        store: spaceCleanerStore,
                        onBack: goBack,
                        onOpenConsole: { target in onOpenConsole(target) }
                    )
                    .transition(pageTransition)

                case .settings:
                    SettingsDetailView(store: store, prefs: store.prefs, moduleSettings: moduleSettings, onBack: goBack)
                        .transition(pageTransition)
                }
            }
            .frame(width: 316)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                LiquidGlassPanelSurface(cornerRadius: 24, isDark: isDark)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.32), Color.white.opacity(0.10)]
                                : [Color.white.opacity(0.85), Color.white.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(isDark ? 0.45 : 0.22),
                radius: 16,
                x: 0,
                y: 9
            )
            .padding(.top, 6)
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.30, dampingFraction: 0.88), value: store.showOtherNetworks)
        }
        .frame(minWidth: 356, maxWidth: 356, maxHeight: .infinity, alignment: .top)
    }

    private func goBack() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            store.navigate(to: .overview)
        }
    }

    private var pageTransition: AnyTransition {
        if store.isGoingForward {
            return .asymmetric(
                insertion: .opacity
                    .combined(with: .offset(x: 16))
                    .combined(with: .scale(scale: 0.985)),
                removal: .opacity
                    .combined(with: .offset(x: -12))
                    .combined(with: .scale(scale: 0.985))
            )
        } else {
            return .asymmetric(
                insertion: .opacity
                    .combined(with: .offset(x: -16))
                    .combined(with: .scale(scale: 0.985)),
                removal: .opacity
                    .combined(with: .offset(x: 12))
                    .combined(with: .scale(scale: 0.985))
            )
        }
    }
}

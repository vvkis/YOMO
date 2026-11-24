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

public enum ConsoleSection: String, CaseIterable, Identifiable {
    case dashboard = "dashboard"
    case duobar = "duobar"
    case audioBluetooth = "audioBluetooth"
    case hidpi = "hidpi"
    case keepAwake = "keepAwake"
    case scrollReverser = "scrollReverser"
    case clipboard = "clipboard"
    case keyboardLock = "keyboardLock"
    case spaceCleaner = "spaceCleaner"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "模块总览"
        case .duobar: return "状态栏"
        case .audioBluetooth: return "蓝牙与音频"
        case .hidpi: return "显示器"
        case .keepAwake: return "防休眠"
        case .scrollReverser: return "滚轮翻转"
        case .clipboard: return "剪贴板"
        case .keyboardLock: return "键盘锁"
        case .spaceCleaner: return "空间清理"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .duobar: return "menubar.rectangle"
        case .audioBluetooth: return "airpodspro"
        case .hidpi: return "display"
        case .keepAwake: return "cup.and.saucer"
        case .scrollReverser: return "computermouse"
        case .clipboard: return "doc.on.clipboard"
        case .keyboardLock: return "keyboard"
        case .spaceCleaner: return "sparkles"
        }
    }
}

@MainActor
final class HubConsoleViewModel: ObservableObject {
    @Published var selectedSection: ConsoleSection = .dashboard
}

struct HubConsoleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: HubConsoleViewModel
    let moduleSettings: ModuleSettings
    let duoBarStore: DuoBarStore
    let displayStore: DisplayHiDPIStore
    let keepAwakeStore: KeepAwakeStore
    let audioBluetoothStore: AudioBluetoothStore
    let scrollReverserStore: ScrollReverserStore
    let clipboardStore: ClipboardStore
    let keyboardLockStore: KeyboardLockStore
    let spaceCleanerStore: SpaceCleanerStore

    var body: some View {
        let isDark = (colorScheme == .dark)

        HStack(spacing: 0) {
            // Left Floating Rounded White Sidebar (WeChat Input style, traffic lights nestled cleanly at top-left)
            VStack(alignment: .leading, spacing: 4) {
                // Clearance matching unified-toolbar traffic lights (● ● ● sit at y ≈ 19–33pt from window top)
                Color.clear
                    .frame(height: 40)

                ForEach(ConsoleSection.allCases) { section in
                    ConsoleSidebarItem(
                        title: section.title,
                        icon: section.icon,
                        isSelected: viewModel.selectedSection == section
                    ) {
                        withAnimation(.easeOut(duration: 0.14)) {
                            viewModel.selectedSection = section
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(ConsoleTheme.accent)
                        .frame(width: 6, height: 6)
                    Text("YOMO · 单进程运行中")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .frame(width: 196)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ConsoleTheme.cardBackground(isDark: isDark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ConsoleTheme.cardBorder(isDark: isDark), lineWidth: 0.7)
                    )
                    .shadow(color: ConsoleTheme.cardShadow(isDark: isDark), radius: 8, x: 0, y: 2)
            )
            .padding(.leading, 10)
            .padding(.vertical, 10)

            // Right Detail Canvas
            Group {
                switch viewModel.selectedSection {
                case .dashboard:
                    DashboardHomeView(
                        moduleSettings: moduleSettings,
                        duoBarStore: duoBarStore,
                        displayStore: displayStore,
                        keepAwakeStore: keepAwakeStore,
                        audioBluetoothStore: audioBluetoothStore,
                        scrollReverserStore: scrollReverserStore,
                        clipboardStore: clipboardStore,
                        keyboardLockStore: keyboardLockStore,
                        spaceCleanerStore: spaceCleanerStore,
                        onSelect: { viewModel.selectedSection = $0 }
                    )
                case .duobar:
                    DuoBarConsoleView(store: duoBarStore)
                case .audioBluetooth:
                    AudioBluetoothConsoleView(store: audioBluetoothStore, moduleSettings: moduleSettings)
                case .hidpi:
                    DisplayHiDPIConsoleView(store: displayStore, moduleSettings: moduleSettings)
                case .keepAwake:
                    KeepAwakeConsoleView(store: keepAwakeStore, moduleSettings: moduleSettings)
                case .scrollReverser:
                    ScrollReverserConsoleView(store: scrollReverserStore, moduleSettings: moduleSettings)
                case .clipboard:
                    ClipboardConsoleView(store: clipboardStore, moduleSettings: moduleSettings)
                case .keyboardLock:
                    KeyboardLockConsoleView(store: keyboardLockStore, moduleSettings: moduleSettings)
                case .spaceCleaner:
                    SpaceCleanerConsoleView(store: spaceCleanerStore, moduleSettings: moduleSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ConsoleTheme.canvasBackground(isDark: isDark))
        .ignoresSafeArea(.all, edges: .top)
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct DashboardHomeView: View {
    @ObservedObject var moduleSettings: ModuleSettings
    @ObservedObject var duoBarStore: DuoBarStore
    @ObservedObject var displayStore: DisplayHiDPIStore
    @ObservedObject var keepAwakeStore: KeepAwakeStore
    @ObservedObject var audioBluetoothStore: AudioBluetoothStore
    @ObservedObject var scrollReverserStore: ScrollReverserStore
    @ObservedObject var clipboardStore: ClipboardStore
    @ObservedObject var keyboardLockStore: KeyboardLockStore
    @ObservedObject var spaceCleanerStore: SpaceCleanerStore
    let onSelect: (ConsoleSection) -> Void

    var body: some View {
        ConsolePageContainer(
            title: "模块总览",
            subtitle: "单进程、单菜单栏入口的原生 macOS 工具箱。停用不需要的模块可保持零后台开销。"
        ) {
            // Core Status Bar Card
            ConsoleCard {
                DashboardModuleRow(
                    icon: "menubar.rectangle",
                    tint: ConsoleTheme.accent,
                    title: "DuoBar 状态栏聚合",
                    subtitle: "电量 \(duoBarStore.battery.percentage)% · 内存 \(Int(round(duoBarStore.memory.usagePercent)))% · \(duoBarStore.wifi.isPoweredOn ? "Wi-Fi 开" : "Wi-Fi 关")",
                    badgeText: "核心常驻",
                    isOn: nil,
                    onOpen: { onSelect(.duobar) }
                )
            }

            // Optional Modular Utilities Card (grouped cleanly like WeChat Input settings list)
            ConsoleCard("工具模块") {
                DashboardModuleRow(
                    icon: "airpodspro",
                    tint: .purple,
                    title: "蓝牙与音频 (AirPods)",
                    subtitle: audioBluetoothStore.primarySubtitle,
                    badgeText: nil,
                    isOn: $moduleSettings.audioBluetoothEnabled,
                    onOpen: { onSelect(.audioBluetooth) }
                )

                ConsoleRowDivider()

                DashboardModuleRow(
                    icon: "display",
                    tint: .indigo,
                    title: "显示器 / HiDPI",
                    subtitle: displayStore.primarySummary,
                    badgeText: nil,
                    isOn: $moduleSettings.hidpiEnabled,
                    onOpen: { onSelect(.hidpi) }
                )

                ConsoleRowDivider()

                DashboardModuleRow(
                    icon: "cup.and.saucer.fill",
                    tint: .orange,
                    title: "防休眠 (KeepAwake)",
                    subtitle: keepAwakeStore.statusSubtitle,
                    badgeText: nil,
                    isOn: Binding(
                        get: { moduleSettings.keepAwakeEnabled },
                        set: { enabled in
                            moduleSettings.keepAwakeEnabled = enabled
                            if !enabled { keepAwakeStore.deactivate() }
                        }
                    ),
                    onOpen: { onSelect(.keepAwake) }
                )

                ConsoleRowDivider()

                DashboardModuleRow(
                    icon: "computermouse.fill",
                    tint: .teal,
                    title: "鼠标滚轮翻转",
                    subtitle: scrollReverserStore.statusSubtitle,
                    badgeText: nil,
                    isOn: Binding(
                        get: { moduleSettings.scrollReverserEnabled },
                        set: { enabled in
                            moduleSettings.scrollReverserEnabled = enabled
                            scrollReverserStore.syncWithModuleEnabled(enabled)
                        }
                    ),
                    onOpen: { onSelect(.scrollReverser) }
                )

                ConsoleRowDivider()

                DashboardModuleRow(
                    icon: "doc.on.clipboard.fill",
                    tint: .blue,
                    title: "历史剪贴板 & OCR",
                    subtitle: clipboardStore.totalCount > 0 ? "已保存 \(clipboardStore.totalCount) 条 · ⇧⌘V 快速唤出" : "等待复制记录 · ⇧⌘V 快速唤出",
                    badgeText: nil,
                    isOn: Binding(
                        get: { moduleSettings.clipboardEnabled },
                        set: { enabled in
                            moduleSettings.clipboardEnabled = enabled
                            clipboardStore.syncWithModuleEnabled(enabled)
                        }
                    ),
                    onOpen: { onSelect(.clipboard) }
                )

                ConsoleRowDivider()

                DashboardModuleRow(
                    icon: keyboardLockStore.isLocked ? "lock.fill" : "keyboard",
                    tint: .pink,
                    title: "键盘锁（清洁模式）",
                    subtitle: keyboardLockStore.statusSubtitle,
                    badgeText: nil,
                    isOn: Binding(
                        get: { moduleSettings.keyboardLockEnabled },
                        set: { enabled in
                            moduleSettings.keyboardLockEnabled = enabled
                            keyboardLockStore.syncWithModuleEnabled(enabled)
                        }
                    ),
                    onOpen: { onSelect(.keyboardLock) }
                )

                ConsoleRowDivider()

                DashboardModuleRow(
                    icon: "sparkles",
                    tint: ConsoleTheme.accent,
                    title: "空间清理（原生安全规则）",
                    subtitle: spaceCleanerStore.overviewSubtitle,
                    badgeText: nil,
                    isOn: $moduleSettings.spaceCleanerEnabled,
                    onOpen: { onSelect(.spaceCleaner) }
                )
            }
        }
    }
}

private struct DashboardModuleRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let badgeText: String?
    let isOn: Binding<Bool>?
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.13))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            ConsoleActionButton("设置…") {
                onOpen()
            }

            if let isOn {
                ConsoleSwitch(isOn: isOn)
            } else if let badgeText {
                Text(badgeText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConsoleTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(ConsoleTheme.accent.opacity(0.12)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12.5)
    }
}

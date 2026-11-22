import SwiftUI
import CoreKit
import DuoBarModule
import DisplayHiDPIModule
import KeepAwakeModule
import AudioBluetoothModule
import ScrollReverserModule
import ClipboardModule

public enum ConsoleSection: String, CaseIterable, Identifiable {
    case dashboard = "dashboard"
    case duobar = "duobar"
    case audioBluetooth = "audioBluetooth"
    case hidpi = "hidpi"
    case keepAwake = "keepAwake"
    case scrollReverser = "scrollReverser"
    case clipboard = "clipboard"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "模块总览"
        case .duobar: return "DuoBar 状态栏"
        case .audioBluetooth: return "蓝牙与音频 (AirPods)"
        case .hidpi: return "显示器 / HiDPI"
        case .keepAwake: return "防休眠"
        case .scrollReverser: return "鼠标滚轮翻转"
        case .clipboard: return "历史剪贴板"
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
        }
    }
}

@MainActor
final class HubConsoleViewModel: ObservableObject {
    @Published var selectedSection: ConsoleSection = .dashboard
}

struct HubConsoleView: View {
    @ObservedObject var viewModel: HubConsoleViewModel
    @ObservedObject var moduleSettings: ModuleSettings
    @ObservedObject var duoBarStore: DuoBarStore
    @ObservedObject var displayStore: DisplayHiDPIStore
    @ObservedObject var keepAwakeStore: KeepAwakeStore
    @ObservedObject var audioBluetoothStore: AudioBluetoothStore
    @ObservedObject var scrollReverserStore: ScrollReverserStore
    @ObservedObject var clipboardStore: ClipboardStore

    var body: some View {
        NavigationSplitView {
            List(ConsoleSection.allCases, selection: $viewModel.selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 195, max: 220)
        } detail: {
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
                }
            }
            .navigationTitle(viewModel.selectedSection.title)
        }
        .frame(minWidth: 680, minHeight: 460)
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
    let onSelect: (ConsoleSection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("单进程、单菜单栏入口的原生 macOS 模块化工具箱。不需要的模块随时关闭，保持零后台开销。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    // Module 1: DuoBar
                    ModuleSummaryCard(
                        icon: "menubar.rectangle",
                        tint: .blue,
                        title: "DuoBar 状态栏聚合",
                        subtitle: "电量 \(duoBarStore.battery.percentage)% · 内存 \(Int(round(duoBarStore.memory.usagePercent)))% · \(duoBarStore.wifi.isPoweredOn ? "Wi-Fi 开" : "Wi-Fi 关")",
                        statusText: "核心常驻",
                        isOn: nil,
                        onOpen: { onSelect(.duobar) }
                    )

                    // Module 2: Audio & AirPods
                    ModuleSummaryCard(
                        icon: "airpodspro",
                        tint: .purple,
                        title: "蓝牙与音频 (AirPods)",
                        subtitle: audioBluetoothStore.primarySubtitle,
                        statusText: moduleSettings.audioBluetoothEnabled ? "已启用" : "已停用",
                        isOn: $moduleSettings.audioBluetoothEnabled,
                        onOpen: { onSelect(.audioBluetooth) }
                    )

                    // Module 3: Display HiDPI
                    ModuleSummaryCard(
                        icon: "display",
                        tint: .indigo,
                        title: "显示器 / HiDPI",
                        subtitle: displayStore.primarySummary,
                        statusText: moduleSettings.hidpiEnabled ? "已启用" : "已停用",
                        isOn: $moduleSettings.hidpiEnabled,
                        onOpen: { onSelect(.hidpi) }
                    )

                    // Module 4: KeepAwake
                    ModuleSummaryCard(
                        icon: "cup.and.saucer.fill",
                        tint: .orange,
                        title: "防休眠 (KeepAwake)",
                        subtitle: keepAwakeStore.statusSubtitle,
                        statusText: moduleSettings.keepAwakeEnabled ? "已启用" : "已停用",
                        isOn: Binding(
                            get: { moduleSettings.keepAwakeEnabled },
                            set: { enabled in
                                moduleSettings.keepAwakeEnabled = enabled
                                if !enabled { keepAwakeStore.deactivate() }
                            }
                        ),
                        onOpen: { onSelect(.keepAwake) }
                    )

                    // Module 5: Scroll Reverser
                    ModuleSummaryCard(
                        icon: "computermouse.fill",
                        tint: .teal,
                        title: "鼠标滚轮翻转",
                        subtitle: scrollReverserStore.statusSubtitle,
                        statusText: moduleSettings.scrollReverserEnabled ? "已启用" : "已停用",
                        isOn: Binding(
                            get: { moduleSettings.scrollReverserEnabled },
                            set: { enabled in
                                moduleSettings.scrollReverserEnabled = enabled
                                scrollReverserStore.syncWithModuleEnabled(enabled)
                            }
                        ),
                        onOpen: { onSelect(.scrollReverser) }
                    )

                    // Module 6: Clipboard History
                    ModuleSummaryCard(
                        icon: "doc.on.clipboard.fill",
                        tint: .cyan,
                        title: "历史剪贴板",
                        subtitle: clipboardStore.totalCount > 0 ? "已保存 \(clipboardStore.totalCount) 条 · ⇧⌘V 唤出" : "等待复制记录 · ⇧⌘V 唤出",
                        statusText: moduleSettings.clipboardEnabled ? "已启用" : "已停用",
                        isOn: Binding(
                            get: { moduleSettings.clipboardEnabled },
                            set: { enabled in
                                moduleSettings.clipboardEnabled = enabled
                                clipboardStore.syncWithModuleEnabled(enabled)
                            }
                        ),
                        onOpen: { onSelect(.clipboard) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }
}

private struct ModuleSummaryCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let statusText: String
    let isOn: Binding<Bool>?
    let onOpen: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tint.opacity(0.16))
                            .frame(width: 34, height: 34)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    if let isOn {
                        Toggle("", isOn: isOn)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    } else {
                        Text(statusText)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()
                    Button("配置 →", action: onOpen)
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            .padding(6)
        }
    }
}

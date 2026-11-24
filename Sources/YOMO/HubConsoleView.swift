import AppKit
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
    case startupItems = "startupItems"

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
        case .startupItems: return "开机启动项"
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
        case .startupItems: return "bolt.shield"
        }
    }
}

@MainActor
final class HubConsoleViewModel: ObservableObject {
    static let defaultSidebarWidth: CGFloat = 196
    static let minSidebarWidth: CGFloat = 160
    static let maxSidebarWidth: CGFloat = 280
    private static let sidebarWidthKey = "console.sidebarWidth"

    @Published var selectedSection: ConsoleSection = .dashboard
    @Published var sidebarWidth: CGFloat

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.sidebarWidthKey)
        if saved >= Self.minSidebarWidth && saved <= Self.maxSidebarWidth {
            self.sidebarWidth = CGFloat(saved)
        } else {
            self.sidebarWidth = Self.defaultSidebarWidth
        }
    }

    func setSidebarWidth(_ raw: CGFloat, persist: Bool = false) {
        let clamped = min(Self.maxSidebarWidth, max(Self.minSidebarWidth, round(raw)))
        if sidebarWidth != clamped {
            sidebarWidth = clamped
        }
        if persist {
            UserDefaults.standard.set(Double(clamped), forKey: Self.sidebarWidthKey)
        }
    }

    func resetSidebarWidth() {
        setSidebarWidth(Self.defaultSidebarWidth, persist: true)
    }
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
    let updateStore: AppUpdateStore

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

                SidebarUpdateFooter(updateStore: updateStore) {
                    withAnimation(.easeOut(duration: 0.14)) {
                        viewModel.selectedSection = .dashboard
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .frame(width: viewModel.sidebarWidth)
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

            // Draggable splitter between left sidebar and right detail canvas (persisted automatically)
            SidebarSplitHandle(
                currentWidth: { viewModel.sidebarWidth },
                onDragWidth: { newWidth in
                    viewModel.setSidebarWidth(newWidth, persist: false)
                },
                onEndWidth: { finalWidth in
                    viewModel.setSidebarWidth(finalWidth, persist: true)
                },
                onReset: {
                    withAnimation(.easeOut(duration: 0.16)) {
                        viewModel.resetSidebarWidth()
                    }
                }
            )
            .zIndex(10)

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
                        updateStore: updateStore,
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
                case .startupItems:
                    StartupItemsConsoleView(store: spaceCleanerStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ConsoleTheme.canvasBackground(isDark: isDark))
        .ignoresSafeArea(.all, edges: .top)
        .frame(minWidth: 820, minHeight: 540)
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
    let updateStore: AppUpdateStore
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
                    title: "空间清理（安全分级规则）",
                    subtitle: spaceCleanerStore.totalReclaimableBytes > 0
                        ? "扫描到可释放 \(SpaceByteFormatter.format(spaceCleanerStore.totalReclaimableBytes)) · 含缓存与卸载残留"
                        : "扫描并勾选清理缓存、开发构建产物与卸载残留",
                    badgeText: nil,
                    isOn: $moduleSettings.spaceCleanerEnabled,
                    onOpen: { onSelect(.spaceCleaner) }
                )

                ConsoleRowDivider()

                DashboardModuleRow(
                    icon: "bolt.shield.fill",
                    tint: .indigo,
                    title: "开机启动项",
                    subtitle: spaceCleanerStore.hasScannedStartupItems
                        ? "可直接开关 \(spaceCleanerStore.toggleableStartupGroups.count) 款应用 · 系统托管 \(spaceCleanerStore.systemManagedStartupGroups.count) 款"
                        : "管理 LaunchAgents / Daemons 开关，并展示系统托管登录项",
                    badgeText: nil,
                    isOn: nil,
                    onOpen: { onSelect(.startupItems) }
                )
            }

            // Software Update Card (GitHub Releases + SHA-256 + In-Place Upgrade preserving all settings)
            AppUpdateCard(store: updateStore)
        }
    }
}

private final class SidebarSplitDragState: ObservableObject {
    @Published var isHovering: Bool = false
    @Published var isDragging: Bool = false
    var dragStartWidth: CGFloat? = nil
    var cursorPushed: Bool = false

    func updateCursor() {
        let shouldShow = isHovering || isDragging
        if shouldShow && !cursorPushed {
            NSCursor.resizeLeftRight.push()
            cursorPushed = true
        } else if !shouldShow && cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }

    func cleanupCursor() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

private struct SidebarSplitHandle: View {
    let currentWidth: () -> CGFloat
    let onDragWidth: (CGFloat) -> Void
    let onEndWidth: (CGFloat) -> Void
    let onReset: () -> Void

    @StateObject private var drag = SidebarSplitDragState()

    var body: some View {
        // Keep compact 10pt visual gap between sidebar card and detail canvas while expanding
        // the interactive hover/drag hit area to a generous 22pt straddling the border.
        Color.clear
            .frame(width: 10)
            .frame(maxHeight: .infinity)
            .overlay {
                ZStack {
                    Color.clear
                    if drag.isHovering || drag.isDragging {
                        Rectangle()
                            .fill(
                                drag.isDragging
                                    ? ConsoleTheme.accent.opacity(0.28)
                                    : Color.primary.opacity(0.10)
                            )
                            .frame(width: 1)
                            .padding(.vertical, 16)
                    }
                    Capsule()
                        .fill(
                            drag.isDragging
                                ? ConsoleTheme.accent.opacity(0.82)
                                : (drag.isHovering ? Color.primary.opacity(0.32) : Color.clear)
                        )
                        .frame(width: 4, height: drag.isDragging ? 64 : 48)
                        .animation(.easeOut(duration: 0.14), value: drag.isHovering)
                        .animation(.easeOut(duration: 0.14), value: drag.isDragging)
                }
                .frame(width: 22)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    drag.isHovering = hovering
                    drag.updateCursor()
                }
                .onDisappear {
                    drag.cleanupCursor()
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if drag.dragStartWidth == nil {
                                drag.dragStartWidth = currentWidth()
                                drag.isDragging = true
                                drag.updateCursor()
                            }
                            let start = drag.dragStartWidth ?? currentWidth()
                            onDragWidth(start + value.translation.width)
                        }
                        .onEnded { value in
                            let start = drag.dragStartWidth ?? currentWidth()
                            drag.dragStartWidth = nil
                            drag.isDragging = false
                            drag.updateCursor()
                            onEndWidth(start + value.translation.width)
                        }
                )
                .onTapGesture(count: 2) {
                    onReset()
                }
                .help("左右拖动调节侧边栏宽度（双击恢复默认）")
            }
    }
}

private struct SidebarUpdateFooter: View {
    @ObservedObject var updateStore: AppUpdateStore
    let onOpenUpdates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let release = updateStore.state.availableRelease {
                Button(action: onOpenUpdates) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("发现新版本 \(release.displayVersion)")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ConsoleTheme.accent)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(ConsoleTheme.accent)
                    .frame(width: 6, height: 6)
                Text("YOMO \(updateStore.displayCurrentVersion) · 单进程")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}

private struct AppUpdateCard: View {
    @ObservedObject var store: AppUpdateStore

    var body: some View {
        ConsoleCard("软件更新") {
            VStack(spacing: 0) {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(iconTint.opacity(0.13))
                            .frame(width: 34, height: 34)
                        Image(systemName: iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(iconTint)
                    }

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 7) {
                            Text("YOMO \(store.displayCurrentVersion)")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .monospacedDigit()

                            if let badge = statusBadge {
                                Text(badge.text)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(badge.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(badge.color.opacity(0.13)))
                            }
                        }

                        Text(statusSubtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(isErrorState ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 10)

                    HStack(spacing: 8) {
                        actionButtons
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)

                // Download progress bar
                if case .downloading(_, let progress, let downloaded, let total) = store.state {
                    ConsoleRowDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(ConsoleTheme.accent)
                        HStack {
                            Text("正在下载更新…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(AppUpdateStore.formatByteSize(downloaded)) / \(AppUpdateStore.formatByteSize(total)) · \(Int(round(progress * 100)))%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                }

                // Release notes preview when a newer version is available
                if let release = store.state.availableRelease, !release.notes.isEmpty {
                    ConsoleRowDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(release.displayVersion) 更新内容")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(release.notes)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 110)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "自动检查更新",
                    subtitle: "有新版本时自动提示，升级后保留原有设置"
                ) {
                    ConsoleSwitch(isOn: $store.autoCheckEnabled)
                }
            }
        }
    }

    private var isErrorState: Bool {
        if case .failed = store.state { return true }
        return false
    }

    private var iconName: String {
        switch store.state {
        case .available, .downloading, .verifying:
            return "arrow.down.circle.fill"
        case .readyToInstall, .installing:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private var iconTint: Color {
        switch store.state {
        case .available, .downloading, .verifying, .readyToInstall, .installing:
            return ConsoleTheme.accent
        case .failed:
            return .orange
        default:
            return .blue
        }
    }

    private var statusBadge: (text: String, color: Color)? {
        switch store.state {
        case .upToDate:
            return ("已是最新", ConsoleTheme.accent)
        case .available(let r):
            return ("新版本 \(r.displayVersion)", ConsoleTheme.accent)
        case .downloading(_, let p, _, _):
            return ("下载中 \(Int(round(p * 100)))%", .blue)
        case .verifying:
            return ("准备中", .blue)
        case .readyToInstall(let r, _, _, _):
            return ("\(r.displayVersion) 已就绪", ConsoleTheme.accent)
        case .installing:
            return ("正在升级", ConsoleTheme.accent)
        case .failed:
            return ("检查失败", .orange)
        default:
            return nil
        }
    }

    private var statusSubtitle: String {
        switch store.state {
        case .idle:
            if let last = store.lastCheckedText {
                return "上次检查：\(last)"
            }
            return "点击右侧检查是否有新版本"
        case .checking:
            return "正在检查更新…"
        case .upToDate:
            if let last = store.lastCheckedText {
                return "当前已是最新版本（\(last)）"
            }
            return "当前已是最新版本"
        case .available(let r):
            let size = AppUpdateStore.formatByteSize(r.assetSizeBytes)
            return size.isEmpty
                ? "发现新版本 \(r.displayVersion)"
                : "发现新版本 \(r.displayVersion)（\(size)）"
        case .downloading(let r, _, _, _):
            return "正在下载 \(r.displayVersion)…"
        case .verifying:
            return "正在验证并准备安装…"
        case .readyToInstall(let r, _, _, _):
            return "\(r.displayVersion) 已就绪，点击即可重启升级"
        case .installing(let r):
            return "正在升级至 \(r.displayVersion)，即将自动重启…"
        case .failed(let msg):
            return msg
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch store.state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .padding(.trailing, 4)
            ConsoleActionButton("检查中…", disabled: true) {}

        case .available:
            ConsoleActionButton("下载更新", variant: .prominent) {
                store.downloadAvailableUpdate()
            }

        case .downloading:
            ConsoleActionButton("取消") {
                store.cancelDownload()
            }

        case .verifying:
            ProgressView()
                .controlSize(.small)
            ConsoleActionButton("准备中…", disabled: true) {}

        case .readyToInstall:
            ConsoleActionButton("立即升级并重启", variant: .prominent) {
                store.installAndRelaunch()
            }

        case .installing:
            ProgressView()
                .controlSize(.small)
            ConsoleActionButton("升级中…", disabled: true) {}

        case .idle, .upToDate, .failed:
            ConsoleActionButton("检查更新", variant: .prominent) {
                store.checkForUpdates(userInitiated: true)
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

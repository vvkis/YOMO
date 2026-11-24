import SwiftUI
import AppKit
import CoreKit

// MARK: - Popover Subpage View (Liquid Glass Quick Cleaner)

public struct SpaceCleanerPopoverView: View {
    @ObservedObject public var store: SpaceCleanerStore
    public let onBack: () -> Void
    public let onOpenConsole: () -> Void

    public init(
        store: SpaceCleanerStore,
        onBack: @escaping () -> Void,
        onOpenConsole: @escaping () -> Void
    ) {
        self.store = store
        self.onBack = onBack
        self.onOpenConsole = onOpenConsole
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubpageHeader(title: "空间清理", onBack: onBack) {
                if store.isScanning {
                    Button {
                        store.cancelScan()
                    } label: {
                        Text("停止")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.primary.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                } else if store.hasScanned && !store.isCleaning {
                    Button {
                        store.startScan()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("重扫")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.primary.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 1. Compact Disk Overview & Action Header
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(heroHeadline)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text(heroSubline)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if !store.isScanning && !store.isCleaning {
                        if !store.hasScanned {
                            Button {
                                store.startScan()
                            } label: {
                                Text("开始扫描")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(ConsoleTheme.accent))
                            }
                            .buttonStyle(.plain)
                        } else if store.selectedItemCount > 0 {
                            Button {
                                store.cleanSelectedItems()
                            } label: {
                                Text("清理 \(SpaceByteFormatter.format(store.selectedBytes))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(ConsoleTheme.accent))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Boot Volume Capacity Bar
                if store.volumeSummary.totalBytes > 0 {
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            let frac = store.volumeSummary.usageFraction
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.12))
                                Capsule()
                                    .fill(frac >= 0.88 ? Color.orange : ConsoleTheme.accent)
                                    .frame(width: max(4, geo.size.width * frac))
                            }
                        }
                        .frame(height: 5)

                        HStack {
                            Text("已用 \(SpaceByteFormatter.format(store.volumeSummary.usedBytes)) / \(SpaceByteFormatter.format(store.volumeSummary.totalBytes))")
                            Spacer()
                            Text("可用 \(SpaceByteFormatter.format(store.volumeSummary.availableBytes))")
                        }
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                }
            }
            .padding(10)
            .glassBentoCard(cornerRadius: 15)

            // 2. Body: Progress / Post-Clean Report / Categorized Checklist
            if store.isScanning || store.isCleaning {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.isScanning ? store.scanProgressText : store.cleanProgressText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .glassBentoCard(cornerRadius: 15)
            } else if let report = store.lastReport {
                popoverReportCard(report)
            } else if !store.hasScanned {
                VStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(ConsoleTheme.accent)
                    Text("安全扫描 Mac 可释放空间")
                        .font(.system(size: 12, weight: .semibold))
                    Text("覆盖应用缓存、浏览器、Xcode/Homebrew/npm/pip 开发缓存、旧安装包与废纸篓，逐项勾选确认后再清理")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 12)
                .glassBentoCard(cornerRadius: 15)
            } else if store.sections.isEmpty || store.totalItemCount == 0 {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(ConsoleTheme.accent)
                    Text("磁盘非常干净")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("未发现超过 512 KB 的可清理缓存或冗余文件")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .glassBentoCard(cornerRadius: 15)
            } else {
                // Quick preset row
                HStack(spacing: 6) {
                    popoverPresetChip("智能推荐") { store.applySmartSelection() }
                    popoverPresetChip("全选") { store.selectAllItems() }
                    popoverPresetChip("不选") { store.clearAllSelections() }
                    Spacer()
                    Text("已选 \(store.selectedItemCount)/\(store.totalItemCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 2)

                // Expandable Categorized Checklist
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(store.sections) { section in
                            PopoverCategoryCard(
                                section: section,
                                isExpanded: store.expandedCategories.contains(section.id),
                                onToggleExpand: { store.toggleCategoryExpanded(section.id) },
                                onToggleCategory: { store.toggleCategorySelection(section.id) },
                                onToggleItem: { itemID in
                                    store.toggleItemSelection(category: section.id, itemID: itemID)
                                },
                                onReveal: { path in store.revealInFinder(path) },
                                onOpenFDA: { store.openFullDiskAccessSettings() },
                                onOpenTrash: { store.openTrashInFinder() }
                            )
                        }
                    }
                }
                .frame(maxHeight: 274)
            }

            // 3. Footer
            HStack {
                Button("开机启动项…") {
                    store.consoleTab = .startup
                    onOpenConsole()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Button("控制台详查…") {
                    store.consoleTab = .cleanup
                    onOpenConsole()
                }
                .font(.system(size: 11.5, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(ConsoleTheme.accent)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .onAppear {
            store.refreshVolumeSummary()
            if !store.hasScanned && !store.isScanning && !store.isCleaning {
                store.startScan()
            }
        }
    }

    private var heroHeadline: String {
        if store.isScanning { return "正在扫描磁盘…" }
        if store.isCleaning { return "正在清理空间…" }
        if let report = store.lastReport {
            return "已释放 \(SpaceByteFormatter.format(report.totalFreedBytes))"
        }
        if store.hasScanned {
            return store.totalReclaimableBytes > 0
                ? "可释放 \(SpaceByteFormatter.format(store.totalReclaimableBytes))"
                : "空间状态良好"
        }
        return "Mac 空间清理"
    }

    private var heroSubline: String {
        if let report = store.lastReport {
            return "清理 \(report.totalCleanedEntries) 项（\(report.totalRemovedFiles) 个文件）· 耗时 \(String(format: "%.1fs", report.durationSeconds))"
        }
        if store.hasScanned {
            return "已勾选 \(store.selectedItemCount) 项 · 预计释放 \(SpaceByteFormatter.format(store.selectedBytes))"
        }
        return "0 子进程原生扫描 · 逐项勾选可控"
    }

    private func popoverPresetChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func popoverReportCard(_ report: CleanupReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(ConsoleTheme.accent)
                Text("本次清理明细")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("返回列表") {
                    store.dismissReport()
                }
                .font(.system(size: 10.5, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(ConsoleTheme.accent)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.categorySummaries) { summary in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: summary.id.symbolName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(summary.id.tintColor)
                                Text(summary.id.shortTitle)
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Text(SpaceByteFormatter.format(summary.freedBytes))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(ConsoleTheme.accent)
                                    .monospacedDigit()
                            }

                            ForEach(summary.cleanedItems) { rec in
                                HStack(spacing: 4) {
                                    Text("· \(rec.title)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.primary.opacity(0.85))
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(rec.action.completedLabel)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                    Text(SpaceByteFormatter.format(rec.freedBytes))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .padding(.leading, 14)
                            }

                            ForEach(summary.skippedItems) { rec in
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.orange)
                                    Text("\(rec.title)：\(rec.skippedReason ?? "已跳过")")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.orange)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 225)

            if report.hadPermissionRestrictions {
                Button {
                    store.openFullDiskAccessSettings()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                        Text("部分受保护目录需授予完全磁盘访问权限 →")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .glassBentoCard(cornerRadius: 15)
    }
}

private struct PopoverCategoryCard: View {
    let section: CleanerCategorySection
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleCategory: () -> Void
    let onToggleItem: (String) -> Void
    let onReveal: (String) -> Void
    let onOpenFDA: () -> Void
    let onOpenTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                if !section.items.isEmpty {
                    Button(action: onToggleCategory) {
                        CleanerCheckGlyph(
                            state: section.isAllSelected ? .all : (section.isPartiallySelected ? .partial : .none),
                            size: 14
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onToggleExpand) {
                    HStack(spacing: 6) {
                        Image(systemName: section.id.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(section.id.tintColor)
                            .frame(width: 15)

                        Text(section.id.shortTitle)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !section.items.isEmpty {
                            Text("\(section.items.count)")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }

                        Spacer(minLength: 4)

                        if section.totalBytes > 0 {
                            Text(SpaceByteFormatter.format(section.totalBytes))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(section.selectedBytes > 0 ? ConsoleTheme.accent : Color.secondary)
                                .monospacedDigit()
                        }

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            if isExpanded {
                if let notice = section.permissionNotice {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(notice)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        HStack(spacing: 8) {
                            Button("前往授权") { onOpenFDA() }
                                .font(.system(size: 10, weight: .semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(ConsoleTheme.accent)
                            Button("在访达中打开") { onOpenTrash() }
                                .font(.system(size: 10, weight: .medium))
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                ForEach(section.items) { item in
                    HStack(spacing: 6) {
                        Button {
                            onToggleItem(item.id)
                        } label: {
                            CleanerCheckGlyph(state: item.isSelected ? .all : .none, size: 13)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                if item.runningAppName != nil {
                                    Text("运行中")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 0.5)
                                        .background(Capsule().fill(Color.orange.opacity(0.16)))
                                } else if item.safety == .review {
                                    Text("确认")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 0.5)
                                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                                }
                            }
                            Text(item.deletionAction == .moveToTrash ? "移至废纸篓 · \(item.displayPath)" : item.displayPath)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 4)

                        Text(SpaceByteFormatter.format(item.byteSize))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        if let path = item.primaryPath {
                            Button {
                                onReveal(path)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("在访达中显示：\(item.displayPath)")
                        }
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 4)
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(7)
        .glassBentoCard(cornerRadius: 13)
    }
}

// MARK: - Hub Console View (WeChat Input Style Full Deep Cleaner)

public struct SpaceCleanerConsoleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject public var store: SpaceCleanerStore
    @ObservedObject public var moduleSettings: ModuleSettings

    public init(store: SpaceCleanerStore, moduleSettings: ModuleSettings) {
        self.store = store
        self.moduleSettings = moduleSettings
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)

        ConsolePageContainer(
            title: "空间清理与启动项",
            subtitle: "纯原生 API 零子进程扫描：按安全等级分级清理缓存与已卸载软件残留，同时透明检测本机开机启动项与僵尸后台代理。"
        ) {
            // 0. Top Tab Switcher (Space Cleanup | Startup Items)
            HStack(spacing: 10) {
                Picker("", selection: $store.consoleTab) {
                    ForEach(SpaceCleanerConsoleTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                Spacer()

                if store.consoleTab == .startup && store.orphanedStartupCount > 0 {
                    Text("发现 \(store.orphanedStartupCount) 个已失效僵尸启动项")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                }
            }

            if store.consoleTab == .startup {
                startupItemsContent(isDark: isDark)
            } else {
            // 1. Module Enable Toggle
            ConsoleCard {
                ConsoleRow(
                    title: "启用「空间清理」模块",
                    subtitle: "在菜单栏概览面板展示空间清理入口；不打开页面时 0 后台扫描开销"
                ) {
                    ConsoleSwitch(isOn: $moduleSettings.spaceCleanerEnabled)
                }
            }

            // 2. Boot Disk & Reclaim Hero Card
            ConsoleCard("磁盘概览与一键清理") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ConsoleTheme.accent.opacity(isDark ? 0.18 : 0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: store.isScanning ? "magnifyingglass" : "sparkles")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(ConsoleTheme.accent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(consoleHeadline)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                            Text(consoleSubline)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Spacer(minLength: 10)

                        HStack(spacing: 8) {
                            if store.isScanning {
                                ConsoleActionButton("停止扫描", variant: .standard) {
                                    store.cancelScan()
                                }
                            } else {
                                ConsoleActionButton(store.hasScanned ? "重新扫描" : "开始扫描", variant: .standard) {
                                    store.startScan()
                                }
                                .disabled(store.isCleaning)
                            }

                            if store.hasScanned && !store.isScanning {
                                ConsoleActionButton(
                                    store.isCleaning
                                        ? "清理中…"
                                        : "清理选中项 (\(SpaceByteFormatter.format(store.selectedBytes)))",
                                    variant: .prominent
                                ) {
                                    store.cleanSelectedItems()
                                }
                                .disabled(store.isCleaning || store.selectedItemCount == 0)
                            }
                        }
                    }

                    // Disk Capacity Progress Bar
                    if store.volumeSummary.totalBytes > 0 {
                        VStack(spacing: 5) {
                            GeometryReader { geo in
                                let frac = store.volumeSummary.usageFraction
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(isDark ? 0.14 : 0.08))
                                    Capsule()
                                        .fill(frac >= 0.88 ? Color.orange : ConsoleTheme.accent)
                                        .frame(width: max(6, geo.size.width * frac))
                                }
                            }
                            .frame(height: 7)

                            HStack {
                                Text("启动磁盘已用 \(SpaceByteFormatter.format(store.volumeSummary.usedBytes)) / \(SpaceByteFormatter.format(store.volumeSummary.totalBytes))")
                                Spacer()
                                Text("当前可用 \(SpaceByteFormatter.format(store.volumeSummary.availableBytes))")
                                    .foregroundStyle(ConsoleTheme.accent)
                                    .fontWeight(.medium)
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                    }

                    if store.isScanning || store.isCleaning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(store.isScanning ? store.scanProgressText : store.cleanProgressText)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            // 3. Detailed Post-Clean Report Card (Shows EXACTLY what was cleaned!)
            if let report = store.lastReport {
                ConsoleCard("本次清理报告（共释放 \(SpaceByteFormatter.format(report.totalFreedBytes))）") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(ConsoleTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("成功清理 \(report.totalCleanedEntries) 个项目，移除 \(report.totalRemovedFiles) 个文件")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("耗时 \(String(format: "%.1f", report.durationSeconds)) 秒 · 已同步刷新磁盘可用容量")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ConsoleActionButton("收起报告", variant: .standard) {
                                store.dismissReport()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        ForEach(report.categorySummaries) { summary in
                            ConsoleRowDivider()
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 7) {
                                    Image(systemName: summary.id.symbolName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(summary.id.tintColor)
                                    Text(summary.id.title)
                                        .font(.system(size: 12.5, weight: .semibold))
                                    Spacer()
                                    Text("释放 \(SpaceByteFormatter.format(summary.freedBytes))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ConsoleTheme.accent)
                                        .monospacedDigit()
                                }

                                ForEach(summary.cleanedItems) { rec in
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(ConsoleTheme.accent)
                                        Text(rec.title)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(rec.action.completedLabel)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                                        Spacer(minLength: 6)
                                        if let warn = rec.skippedReason {
                                            Text(warn)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(.orange)
                                                .lineLimit(1)
                                        }
                                        Text("\(rec.removedFileCount) 项 · \(SpaceByteFormatter.format(rec.freedBytes))")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    .padding(.leading, 18)
                                }

                                ForEach(summary.skippedItems) { rec in
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                        Text(rec.title)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(rec.skippedReason ?? "已跳过")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.leading, 18)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }

                        if report.hadPermissionRestrictions {
                            ConsoleRowDivider()
                            HStack(spacing: 10) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(.orange)
                                Text("部分受 macOS TCC 保护的缓存或废纸篓项目需要「完全磁盘访问权限」才能清理。")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ConsoleActionButton("前往授权", variant: .standard) {
                                    store.openFullDiskAccessSettings()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }

            // 4. Selection Presets & Categorized Expandable Checklist
            if store.hasScanned && !store.isScanning {
                if store.sections.isEmpty || store.totalItemCount == 0 {
                    ConsoleCard {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(ConsoleTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("未发现需要清理的冗余项")
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text("所有已纳管的安全缓存、开发构建产物与安装包均已处于干净状态。")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("扫描清单（共 \(store.totalItemCount) 项 · 已勾选 \(store.selectedItemCount) 项，预计释放 \(SpaceByteFormatter.format(store.selectedBytes))）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Spacer()

                        ConsoleActionButton("智能推荐", variant: .standard) {
                            store.applySmartSelection()
                        }
                        ConsoleActionButton("全选", variant: .standard) {
                            store.selectAllItems()
                        }
                        ConsoleActionButton("取消全选", variant: .standard) {
                            store.clearAllSelections()
                        }
                    }
                    .padding(.horizontal, 2)

                    ForEach(store.sections) { section in
                        ConsoleCategoryCard(
                            section: section,
                            isExpanded: store.expandedCategories.contains(section.id),
                            onToggleExpand: { store.toggleCategoryExpanded(section.id) },
                            onToggleCategory: { store.toggleCategorySelection(section.id) },
                            onToggleItem: { itemID in
                                store.toggleItemSelection(category: section.id, itemID: itemID)
                            },
                            onReveal: { path in store.revealInFinder(path) },
                            onOpenFDA: { store.openFullDiskAccessSettings() },
                            onOpenTrash: { store.openTrashInFinder() }
                        )
                    }
                }
            }

            // 5. Safety Architecture Explainer Card
            ConsoleCard("安全清理规则说明") {
                ConsoleRow(
                    title: "严格限定用户目录与白名单规则",
                    subtitle: "绝不触碰 /System、/Library 系统文件、SSH/钥匙串凭据、iCloud 云盘、浏览器密码/Cookie、Spotify 离线音乐、微信聊天记录与 YOMO 剪贴板"
                ) { EmptyView() }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "分级保护、运行中避让与软件残留检测",
                    subtitle: "「极安全 / 推荐清理」默认勾选；运行中的浏览器/IDE 缓存自动取消默认勾选；已卸载软件残留经已装 App 与 LaunchServices 双重核验，与安装包/大文件一样默认不选且清理时移至废纸篓，随时可还原"
                ) { EmptyView() }
            }
            }
        }
        .onAppear {
            store.refreshVolumeSummary()
            if store.consoleTab == .startup {
                if !store.hasScannedStartupItems && !store.isScanningStartupItems {
                    store.refreshStartupItems()
                }
            } else if !store.hasScanned && !store.isScanning && !store.isCleaning {
                store.startScan()
            }
        }
        .onChange(of: store.consoleTab) { _, newTab in
            if newTab == .startup && !store.hasScannedStartupItems && !store.isScanningStartupItems {
                store.refreshStartupItems()
            } else if newTab == .cleanup && !store.hasScanned && !store.isScanning && !store.isCleaning {
                store.startScan()
            }
        }
    }

    @ViewBuilder
    private func startupItemsContent(isDark: Bool) -> some View {
        // 1. Startup Summary Card
        ConsoleCard("开机启动项与后台代理总览") {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.indigo.opacity(isDark ? 0.22 : 0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.indigo)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isScanningStartupItems
                         ? "正在检测开机启动项与后台服务…"
                         : "共检测到 \(store.startupItems.count) 个开机启动与后台项")
                        .font(.system(size: 15.5, weight: .bold))
                        .monospacedDigit()
                    Text("已开启 \(store.enabledStartupCount) 项 · 运行中 \(store.runningStartupCount) 项 · 已失效残留 \(store.orphanedStartupCount) 项")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    ConsoleActionButton(store.isScanningStartupItems ? "扫描中…" : "重新检测", variant: .standard) {
                        store.refreshStartupItems()
                    }
                    .disabled(store.isScanningStartupItems)

                    ConsoleActionButton("系统登录项设置…", variant: .prominent) {
                        store.openLoginItemsSettings()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }

        if let msg = store.startupStatusMessage, !msg.isEmpty {
            ConsoleBanner(
                icon: "checkmark.circle.fill",
                tint: ConsoleTheme.accent,
                title: msg,
                subtitle: "用户代理支持随时切换开关；系统级与 BTM 项受 macOS 保护请在系统设置中调整。"
            )
        }

        // 2. Filter Bar
        HStack(spacing: 8) {
            Picker("", selection: $store.startupFilter) {
                ForEach(StartupItemFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            Spacer()

            Text("显示 \(store.filteredStartupItems.count) 项")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 2)

        // 3. Startup Items List
        let items = store.filteredStartupItems
        if store.isScanningStartupItems && items.isEmpty {
            ConsoleCard {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在解析 LaunchAgents、LaunchDaemons 与应用内嵌登录助手…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if items.isEmpty {
            ConsoleCard {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(ConsoleTheme.accent)
                    Text(store.startupFilter == .orphaned
                         ? "未检测到目标程序已丢失的僵尸启动项"
                         : "当前筛选条件下暂无启动项")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ConsoleCard("检测结果") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            ConsoleRowDivider()
                        }
                        ConsoleStartupItemRow(
                            item: item,
                            appIcon: store.appIcon(for: item),
                            isToggling: store.togglingStartupItemID == item.id,
                            onToggleEnabled: item.canToggleDirectly ? { newValue in
                                store.setUserStartupItemEnabled(item, enabled: newValue)
                            } : nil,
                            onOpenSystemSettings: { store.openLoginItemsSettings() },
                            onReveal: { store.revealInFinder(item.sourcePath) },
                            onTrash: (item.canMoveToTrash && item.isOrphanedBinary) ? { store.trashUserStartupItem(item) } : nil
                        )
                    }
                }
            }
        }

        // 4. Guidance Card
        ConsoleCard("权限边界与层级说明") {
            ConsoleRow(
                title: "用户代理（~/Library/LaunchAgents）· 可直接开关",
                subtitle: "仅对当前用户登录后生效，归个人账号所有。关闭后配置会无损暂存并立即停用，随时可重新开启，无需管理员权限"
            ) { EmptyView() }

            ConsoleRowDivider()

            ConsoleRow(
                title: "系统代理 & 系统守护进程（/Library）· 建议前往系统设置修改",
                subtitle: "对所有用户或开机 root 权限生效，受 macOS 权限保护。YOMO 不安装常驻 root 守护程序，点击右侧「系统设置」即可在官方「登录项与扩展」中安全开关"
            ) { EmptyView() }
        }
    }

    private var consoleHeadline: String {
        if store.isScanning { return "正在深度扫描本机可释放空间…" }
        if store.isCleaning { return "正在安全执行清理…" }
        if store.hasScanned {
            return store.totalReclaimableBytes > 0
                ? "发现 \(SpaceByteFormatter.format(store.totalReclaimableBytes)) 可释放空间"
                : "磁盘状态良好，暂无大体积冗余缓存"
        }
        return "点击「开始扫描」分析可释放空间"
    }

    private var consoleSubline: String {
        if store.hasScanned {
            return "已勾选 \(store.selectedItemCount) / \(store.totalItemCount) 项 · 本次将释放 \(SpaceByteFormatter.format(store.selectedBytes))"
        }
        return "扫描应用缓存、浏览器、Xcode/Homebrew/npm/pip/Cargo/Gradle、旧安装包、大文件与废纸篓"
    }
}

private struct ConsoleCategoryCard: View {
    let section: CleanerCategorySection
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleCategory: () -> Void
    let onToggleItem: (String) -> Void
    let onReveal: (String) -> Void
    let onOpenFDA: () -> Void
    let onOpenTrash: () -> Void

    var body: some View {
        ConsoleCard {
            VStack(alignment: .leading, spacing: 0) {
                // Category Header Row
                HStack(spacing: 11) {
                    if !section.items.isEmpty {
                        Button(action: onToggleCategory) {
                            CleanerCheckGlyph(
                                state: section.isAllSelected ? .all : (section.isPartiallySelected ? .partial : .none),
                                size: 16
                            )
                        }
                        .buttonStyle(.plain)
                        .help(section.isAllSelected ? "取消勾选此分类" : "全选此分类")
                    }

                    Button(action: onToggleExpand) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(section.id.tintColor.opacity(0.14))
                                    .frame(width: 30, height: 30)
                                Image(systemName: section.id.symbolName)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(section.id.tintColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(section.id.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    if !section.items.isEmpty {
                                        Text("\(section.selectedCount)/\(section.items.count) 项")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                Text(section.id.subtitle)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(SpaceByteFormatter.format(section.totalBytes))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(section.selectedBytes > 0 ? ConsoleTheme.accent : Color.primary)
                                    .monospacedDigit()
                                if section.selectedBytes > 0 && section.selectedBytes < section.totalBytes {
                                    Text("已选 \(SpaceByteFormatter.format(section.selectedBytes))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(ConsoleTheme.accent)
                                        .monospacedDigit()
                                }
                            }

                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if isExpanded {
                    if let notice = section.permissionNotice {
                        ConsoleRowDivider()
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.orange)
                            Text(notice)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                            ConsoleActionButton("完全磁盘访问", variant: .standard) {
                                onOpenFDA()
                            }
                            ConsoleActionButton("打开废纸篓", variant: .standard) {
                                onOpenTrash()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    ForEach(section.items) { item in
                        ConsoleRowDivider()
                        ConsoleCleanerItemRow(
                            item: item,
                            onToggle: { onToggleItem(item.id) },
                            onReveal: {
                                if let p = item.primaryPath {
                                    onReveal(p)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct ConsoleCleanerItemRow: View {
    let item: CleanerItem
    let onToggle: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onToggle) {
                CleanerCheckGlyph(state: item.isSelected ? .all : .none, size: 15)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    safetyPill(item.safety)

                    if let running = item.runningAppName {
                        Text("\(running) 运行中 · 默认跳过")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                    }
                }

                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                    Text(item.deletionAction.actionLabel)
                    if item.fileCount > 1 {
                        Text("· \(item.fileCount) 个文件")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            }

            Spacer(minLength: 8)

            Text(SpaceByteFormatter.format(item.byteSize))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(item.isSelected ? ConsoleTheme.accent : Color.secondary)
                .monospacedDigit()

            if item.primaryPath != nil {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .help("在访达中查看位置")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func safetyPill(_ safety: CleanerSafetyLevel) -> some View {
        let color: Color = {
            switch safety {
            case .safe: return ConsoleTheme.accent
            case .recommended: return .blue
            case .review: return .orange
            }
        }()
        return Text(safety.badgeTitle)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.13)))
    }
}

// MARK: - Shared Tri-State Checkbox Glyph

private enum CleanerCheckState {
    case none
    case partial
    case all
}

private struct CleanerCheckGlyph: View {
    let state: CleanerCheckState
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(state == .none ? Color.clear : ConsoleTheme.accent)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(
                            state == .none ? Color.primary.opacity(0.32) : ConsoleTheme.accent,
                            lineWidth: 1.25
                        )
                )

            if state == .all {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.60, weight: .bold))
                    .foregroundStyle(.white)
            } else if state == .partial {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: size * 0.55, height: 1.8)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .contentShape(Rectangle())
    }
}

private struct ConsoleStartupItemRow: View {
    let item: StartupItemInfo
    let appIcon: NSImage?
    let isToggling: Bool
    let onToggleEnabled: ((Bool) -> Void)?
    let onOpenSystemSettings: () -> Void
    let onReveal: () -> Void
    let onTrash: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            if let appIcon, !item.isOrphanedBinary {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((item.isOrphanedBinary ? Color.red : item.scope.tintColor).opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: item.isOrphanedBinary ? "exclamationmark.triangle.fill" : "bolt.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item.isOrphanedBinary ? Color.red : item.scope.tintColor)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    pill(item.scope.badgeTitle, color: item.scope.tintColor)

                    if item.isOrphanedBinary {
                        pill("程序已卸载 · 僵尸残留", color: .red)
                    } else if item.isEnabled {
                        pill(item.isRunning ? "已开启 · 运行中" : "已开启", color: ConsoleTheme.accent)
                    } else {
                        pill("已关闭", color: .secondary)
                    }

                    if item.keepAlive && item.isEnabled && !item.isOrphanedBinary {
                        pill("后台保活", color: .orange)
                    }
                }

                Text(item.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.displaySourcePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let exec = item.executablePath, !exec.isEmpty {
                        Text("→")
                        Text(exec)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let onTrash {
                    ConsoleActionButton("清理残留", variant: .destructive, action: onTrash)
                } else if let onToggleEnabled {
                    if isToggling {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 40)
                    } else {
                        ConsoleSwitch(
                            isOn: Binding(
                                get: { item.isEnabled },
                                set: { onToggleEnabled($0) }
                            )
                        )
                    }
                } else {
                    ConsoleActionButton("系统设置", variant: .standard, action: onOpenSystemSettings)
                        .help("系统级或 BTM 托管项受 macOS 权限保护，点击前往「登录项与扩展」调整")
                }

                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .help("在访达中查看配置文件：\(item.displaySourcePath)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.13)))
    }
}

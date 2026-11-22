import SwiftUI
import CoreKit

public struct ClipboardPopoverView: View {
    @ObservedObject public var store: ClipboardStore
    public let onBack: () -> Void
    public let onItemCopied: () -> Void
    public let onOpenConsole: () -> Void

    public init(
        store: ClipboardStore,
        onBack: @escaping () -> Void,
        onItemCopied: @escaping () -> Void,
        onOpenConsole: @escaping () -> Void
    ) {
        self.store = store
        self.onBack = onBack
        self.onItemCopied = onItemCopied
        self.onOpenConsole = onOpenConsole
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubpageHeader(title: "历史剪贴板", onBack: onBack) {
                if store.hasUnpinnedItems {
                    Button {
                        store.clearUnpinned()
                    } label: {
                        Text("清空")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.primary.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .help("清空未置顶的历史记录")
                }
            }

            // 1. Compact Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索文本或来源应用…", text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !store.searchQuery.isEmpty {
                    Button {
                        store.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .glassBentoCard(cornerRadius: 11)

            // 2. Filter Segmented Picker
            Picker("", selection: $store.activeFilter) {
                ForEach(ClipboardFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // 3. History List Bento Card
            let filtered = store.filteredEntries
            VStack(spacing: 0) {
                if filtered.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(store.entries.isEmpty ? "暂无剪贴板记录" : "没有匹配的记录")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(store.entries.isEmpty ? "复制文本或截图后将自动记录，密码类敏感内容会自动过滤" : "尝试切换筛选或清空搜索词")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 12)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(filtered) { item in
                                ClipboardEntryRow(
                                    entry: item,
                                    thumbnail: store.thumbnail(for: item),
                                    sourceIcon: store.sourceIcon(for: item),
                                    relativeTime: store.relativeTimeText(for: item.createdAt),
                                    onSelect: {
                                        store.copyEntry(item, triggerAutoPaste: true)
                                        onItemCopied()
                                    },
                                    onTogglePin: {
                                        store.togglePin(item)
                                    },
                                    onDelete: {
                                        store.deleteEntry(item)
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 288)
                }
            }
            .padding(6)
            .glassBentoCard(cornerRadius: 15)

            // 4. Footer
            HStack {
                Text("共 \(store.totalCount) 条 · ⇧⌘V 快速唤出")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Button("设置…") {
                    onOpenConsole()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .onAppear {
            store.setUIActive(true)
        }
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let thumbnail: NSImage?
    let sourceIcon: NSImage?
    let relativeTime: String
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @StateObject private var hover = HoverTracker()

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    // Left Visual: Image thumbnail or Source App icon
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 34, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.6)
                            )
                    } else if let sourceIcon {
                        Image(nsImage: sourceIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: entry.kind == .image ? "photo" : "doc.text")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.singleLinePreview)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 4) {
                            if entry.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.orange)
                            }
                            if let app = entry.sourceAppName, !app.isEmpty {
                                Text(app)
                                    .lineLimit(1)
                                Text("·")
                            }
                            Text(relativeTime)
                            if entry.kind == .text && entry.characterCount > 0 {
                                Text("· \(entry.characterCount)字")
                            }
                        }
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }

                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Quick Pin & Delete actions (always show orange pin when pinned; show both on hover)
            if hover.isHovering || entry.isPinned {
                HStack(spacing: 4) {
                    Button(action: onTogglePin) {
                        Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(entry.isPinned ? Color.orange : Color.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(entry.isPinned ? "取消置顶" : "置顶此条")

                    if hover.isHovering {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("删除此条")
                    }
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hover.isHovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { hover.isHovering = $0 }
    }
}

public struct ClipboardConsoleView: View {
    @ObservedObject public var store: ClipboardStore
    @ObservedObject public var moduleSettings: ModuleSettings

    public init(store: ClipboardStore, moduleSettings: ModuleSettings) {
        self.store = store
        self.moduleSettings = moduleSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text("本地轻量剪贴板历史，支持文本与图片预览、置顶与搜索；自动遵循密码管理器隐私标记，绝不记录密码类敏感剪贴板内容。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("启用模块", isOn: Binding(
                        get: { moduleSettings.clipboardEnabled },
                        set: { enabled in
                            moduleSettings.clipboardEnabled = enabled
                            store.syncWithModuleEnabled(enabled)
                        }
                    ))
                    .toggleStyle(.switch)
                }

                GroupBox("记录与快捷键设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最多保留条数（不含置顶）")
                            Spacer()
                            Picker("", selection: $store.maxHistoryCount) {
                                Text("30 条").tag(30)
                                Text("50 条").tag(50)
                                Text("100 条").tag(100)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                            .labelsHidden()
                        }

                        Toggle("记录复制的图片与截图（本地最多保留最近 10 张）", isOn: $store.saveImages)
                            .toggleStyle(.switch)

                        Toggle("全局快捷键 ⇧⌘V 快速唤出历史剪贴板", isOn: $store.globalHotkeyEnabled)
                            .toggleStyle(.switch)

                        HStack {
                            Toggle("点击条目后自动粘贴到当前应用（需辅助功能权限）", isOn: $store.autoPasteEnabled)
                                .toggleStyle(.switch)
                            if store.autoPasteEnabled && !store.hasAccessibilityForAutoPaste {
                                Button("授权辅助功能") {
                                    store.openAccessibilitySettings()
                                }
                                .controlSize(.small)
                            }
                        }

                        Divider()

                        HStack {
                            Text("当前已保存 \(store.totalCount) 条记录（仅保存在本机，权限 0600）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("清空未置顶") {
                                store.clearUnpinned()
                            }
                            .disabled(!store.hasUnpinnedItems)
                            Button("全部清空", role: .destructive) {
                                store.clearAll()
                            }
                            .disabled(store.entries.isEmpty)
                        }
                    }
                    .padding(6)
                }

                GroupBox("最近记录") {
                    VStack(spacing: 4) {
                        if store.entries.isEmpty {
                            Text("暂无剪贴板历史记录")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        } else {
                            ForEach(store.entries.prefix(15)) { item in
                                ClipboardEntryRow(
                                    entry: item,
                                    thumbnail: store.thumbnail(for: item),
                                    sourceIcon: store.sourceIcon(for: item),
                                    relativeTime: store.relativeTimeText(for: item.createdAt),
                                    onSelect: {
                                        store.copyEntry(item, triggerAutoPaste: false)
                                    },
                                    onTogglePin: {
                                        store.togglePin(item)
                                    },
                                    onDelete: {
                                        store.deleteEntry(item)
                                    }
                                )
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .onAppear {
            store.setUIActive(true)
        }
    }
}

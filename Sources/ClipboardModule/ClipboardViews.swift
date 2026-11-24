import SwiftUI
import AppKit
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
            SubpageHeader(
                title: "历史剪贴板",
                onBack: {
                    if store.activeOCRResult != nil {
                        store.dismissOCRResult()
                    } else {
                        onBack()
                    }
                }
            ) {
                if store.activeOCRResult == nil && store.hasUnpinnedItems {
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

            if let ocrResult = store.activeOCRResult {
                ClipboardOCRResultPanel(
                    result: ocrResult,
                    thumbnail: store.entry(for: ocrResult.entryID).flatMap { store.thumbnail(for: $0) },
                    mergeLines: $store.ocrMergeLines,
                    toastMessage: store.ocrToastMessage,
                    onCopyText: { text in
                        store.copyOCRText(text)
                    },
                    onOpenURL: { urlString in
                        store.openBarcodeURL(urlString)
                    },
                    onClose: {
                        store.dismissOCRResult()
                    }
                )
            } else {
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
                            LazyVStack(spacing: 2) {
                                ForEach(filtered) { item in
                                    ClipboardEntryRow(
                                        entry: item,
                                        thumbnail: store.thumbnail(for: item),
                                        sourceIcon: store.sourceIcon(for: item),
                                        relativeTime: store.relativeTimeText(for: item.createdAt),
                                        isScanningOCR: store.ocrScanningEntryID == item.id,
                                        isRecentlyCopied: store.lastCopiedEntryID == item.id,
                                        onSelect: {
                                            let didAutoPaste = store.copyEntry(item, triggerAutoPaste: true)
                                            if didAutoPaste {
                                                onItemCopied()
                                            }
                                        },
                                        onOCR: item.kind == .image ? {
                                            store.recognizeEntry(item)
                                        } : nil,
                                        onTogglePin: {
                                            store.togglePin(item)
                                        },
                                        onDelete: {
                                            store.deleteEntry(item)
                                        },
                                        onHoverChanged: { isHovering in
                                            if isHovering {
                                                store.setHoveredEntry(item)
                                            } else {
                                                store.clearHoveredEntry(item.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 256)
                    }
                }
                .padding(6)
                .glassBentoCard(cornerRadius: 15)
            }

            // 4. Compact Auto-Cleanup Bar
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.autoCleanupEnabled ? Color.accentColor : Color.secondary)

                Text("自动清理")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                if store.autoCleanupEnabled {
                    HStack(spacing: 4) {
                        TextField("", value: $store.autoCleanupHours, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .frame(width: 34)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                        Text("小时")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Stepper(
                            "",
                            value: $store.autoCleanupHours,
                            in: ClipboardStore.minAutoCleanupHours...ClipboardStore.maxAutoCleanupHours
                        )
                        .labelsHidden()
                        .controlSize(.mini)
                    }
                    .help("自定义保留时长（1–720 小时），过期未置顶记录将自动清理")
                }

                Toggle("", isOn: $store.autoCleanupEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("开启后按自定义小时数自动清理过期的未置顶记录")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassBentoCard(cornerRadius: 12)

            // 5. Footer
            HStack {
                Text("按住空格预览 · 共 \(store.totalCount) 条 · ⇧⌘V")
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
            store.beginSpacePreviewSession()
        }
        .onDisappear {
            store.endSpacePreviewSession()
            store.dismissOCRResult()
        }
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let thumbnail: NSImage?
    let sourceIcon: NSImage?
    let relativeTime: String
    let isScanningOCR: Bool
    let isRecentlyCopied: Bool
    let onSelect: () -> Void
    let onOCR: (() -> Void)?
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onHoverChanged: (Bool) -> Void

    @StateObject private var hover = HoverTracker()

    var body: some View {
        HStack(spacing: 6) {
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
            .help("点击即复制 · 悬停按住空格可预览全部内容")

            // Quick Copy feedback / OCR (for images) / Pin & Delete actions
            HStack(spacing: 4) {
                if isRecentlyCopied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("已复制")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundStyle(ConsoleTheme.accent)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ConsoleTheme.accent.opacity(0.14)))
                } else if hover.isHovering && onOCR == nil {
                    Button(action: onSelect) {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9, weight: .medium))
                            Text("复制")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .help("复制到剪贴板")
                }

                if let onOCR, !isRecentlyCopied {
                    Button(action: onOCR) {
                        HStack(spacing: 3) {
                            if isScanningOCR {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "text.viewfinder")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            Text("OCR")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(hover.isHovering || isScanningOCR ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(
                                    hover.isHovering || isScanningOCR
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.primary.opacity(0.07)
                                )
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isScanningOCR)
                    .help("识别图片中的文字或二维码（原图本地离线识别）")
                }

                if hover.isHovering || entry.isPinned {
                    Button(action: onTogglePin) {
                        Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(entry.isPinned ? Color.orange : Color.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(entry.isPinned ? "取消置顶" : "置顶此条")
                }

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
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isRecentlyCopied
                        ? ConsoleTheme.accent.opacity(0.14)
                        : (hover.isHovering ? Color.primary.opacity(0.08) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isRecentlyCopied ? ConsoleTheme.accent.opacity(0.45) : Color.clear,
                    lineWidth: 0.8
                )
        )
        .onHover { isHovering in
            hover.isHovering = isHovering
            onHoverChanged(isHovering)
        }
    }
}

private struct ClipboardOCRResultPanel: View {
    let result: ClipboardOCRResult
    let thumbnail: NSImage?
    @Binding var mergeLines: Bool
    let toastMessage: String?
    let onCopyText: (String) -> Void
    let onOpenURL: (String) -> Void
    let onClose: () -> Void

    private var displayedText: String {
        mergeLines ? result.mergedText : result.rawText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header bar: Back to list + image thumbnail + char count
            HStack(spacing: 8) {
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("返回列表")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.10)))
                }
                .buttonStyle(.plain)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Text(result.sourceLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if !displayedText.isEmpty {
                    Text("\(displayedText.count) 字")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let errorMessage = result.errorMessage {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            } else if !result.hasContent {
                VStack(spacing: 6) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("未检测到文字或二维码")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("可尝试截图更清晰或放大区域后再试")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
            } else {
                // Barcodes / QR codes section
                if !result.barcodes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.barcodes) { code in
                            HStack(spacing: 7) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(code.symbology)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text(code.payload)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }

                                Spacer(minLength: 4)

                                Button("复制") {
                                    onCopyText(code.payload)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.10)))

                                if code.isWebURL {
                                    Button("打开链接") {
                                        onOpenURL(code.payload)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor))
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.10))
                            )
                        }
                    }
                }

                // Recognized Text section (freely selectable with mouse)
                if !displayedText.isEmpty {
                    SelectableOCRTextView(text: displayedText)
                        .frame(height: result.barcodes.isEmpty ? 200 : 140)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }

                // Bottom Action Bar
                HStack(spacing: 8) {
                    if !result.rawText.isEmpty {
                        Button {
                            mergeLines.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mergeLines ? "checkmark.circle.fill" : "text.alignleft")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(mergeLines ? Color.accentColor : Color.secondary)
                                Text("合并换行")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(mergeLines ? .primary : .secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(
                                Capsule().fill(mergeLines ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("合并硬换行为连续段落，适合复制网页或 PDF 文字")
                    }

                    if let toastMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.green)
                            Text(toastMessage)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }

                    Spacer()

                    if !displayedText.isEmpty {
                        Button {
                            onCopyText(displayedText)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text("复制全文")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                        .help("写入当前系统剪贴板（不会打断当前窗口，也不会插入多余历史记录）")
                    }
                }
            }
        }
        .padding(10)
        .glassBentoCard(cornerRadius: 15)
    }
}

private struct SelectableOCRTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.textColor = NSColor.labelColor
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
        ConsolePageContainer(
            title: "剪贴板",
            subtitle: "本地轻量历史剪贴板，支持图片离线 Vision OCR 与二维码识别；自动过滤密码管理器敏感内容。",
            trailing: {
                HStack(spacing: 8) {
                    Text("启用模块")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    ConsoleSwitch(isOn: Binding(
                        get: { moduleSettings.clipboardEnabled },
                        set: { enabled in
                            moduleSettings.clipboardEnabled = enabled
                            store.syncWithModuleEnabled(enabled)
                        }
                    ))
                }
            }
        ) {
            // Card 1: Capture & Shortcuts
            ConsoleCard("记录与快捷键") {
                ConsoleRow(
                    title: "最多保留条数",
                    subtitle: "不含已置顶的常用收藏条目"
                ) {
                    Picker("", selection: $store.maxHistoryCount) {
                        Text("30 条").tag(30)
                        Text("50 条").tag(50)
                        Text("100 条").tag(100)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 195)
                    .labelsHidden()
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "记录复制的图片与截图",
                    subtitle: "支持离线文字提取与二维码解析，本地最多保留最近 10 张未置顶图片"
                ) {
                    ConsoleSwitch(isOn: $store.saveImages)
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "全局快捷键唤出",
                    subtitle: "任意应用中按下 ⇧⌘V 立即弹出历史剪贴板"
                ) {
                    ConsoleSwitch(isOn: $store.globalHotkeyEnabled)
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "点击条目后自动粘贴",
                    subtitle: "将选中内容写回剪贴板并自动向当前应用发送 ⌘V（需辅助功能权限）"
                ) {
                    HStack(spacing: 10) {
                        if store.autoPasteEnabled && !store.hasAccessibilityForAutoPaste {
                            ConsoleActionButton("去授权") {
                                store.openAccessibilitySettings()
                            }
                        }
                        ConsoleSwitch(isOn: $store.autoPasteEnabled)
                    }
                }
            }

            // Card 2: Auto-Cleanup & Local Storage
            ConsoleCard("自动清理与本地缓存") {
                ConsoleRow(
                    title: "自动清理过期记录",
                    subtitle: "超过设定小时数的未置顶文本与图片将自动清除（保留已置顶条目）"
                ) {
                    ConsoleSwitch(isOn: $store.autoCleanupEnabled)
                }

                if store.autoCleanupEnabled {
                    ConsoleRowDivider()

                    HStack(spacing: 10) {
                        Text("保留时长")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 5) {
                            ForEach([1, 6, 12, 24, 72], id: \.self) { preset in
                                let isSelected = (store.autoCleanupHours == preset)
                                Button("\(preset)h") {
                                    store.autoCleanupHours = preset
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? ConsoleTheme.accent : Color.primary.opacity(0.06))
                                )
                            }
                        }

                        Spacer()

                        TextField("", value: $store.autoCleanupHours, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)

                        Text("小时")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Stepper(
                            "",
                            value: $store.autoCleanupHours,
                            in: ClipboardStore.minAutoCleanupHours...ClipboardStore.maxAutoCleanupHours
                        )
                        .labelsHidden()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "本机私有存储（权限 0600）",
                    subtitle: "当前共保存 \(store.totalCount) 条记录，仅存储在本机 Application Support 目录"
                ) {
                    HStack(spacing: 8) {
                        ConsoleActionButton("打开目录") {
                            store.openStorageFolder()
                        }
                        ConsoleActionButton("清空未置顶", disabled: !store.hasUnpinnedItems) {
                            store.clearUnpinned()
                        }
                        ConsoleActionButton("全部清空", variant: .destructive, disabled: store.entries.isEmpty) {
                            store.clearAll()
                        }
                    }
                }
            }

            // Card 3: Recent History & Inline OCR
            ConsoleCard("最近记录") {
                VStack(spacing: 4) {
                    if let ocrResult = store.activeOCRResult {
                        ClipboardOCRResultPanel(
                            result: ocrResult,
                            thumbnail: store.entry(for: ocrResult.entryID).flatMap { store.thumbnail(for: $0) },
                            mergeLines: $store.ocrMergeLines,
                            toastMessage: store.ocrToastMessage,
                            onCopyText: { text in
                                store.copyOCRText(text)
                            },
                            onOpenURL: { urlString in
                                store.openBarcodeURL(urlString)
                            },
                            onClose: {
                                store.dismissOCRResult()
                            }
                        )
                    } else if store.entries.isEmpty {
                        ConsoleRow(title: "暂无剪贴板历史记录", subtitle: "复制任意文本或截图后将自动出现在这里") {
                            EmptyView()
                        }
                    } else {
                        ForEach(store.entries.prefix(15)) { item in
                            ClipboardEntryRow(
                                entry: item,
                                thumbnail: store.thumbnail(for: item),
                                sourceIcon: store.sourceIcon(for: item),
                                relativeTime: store.relativeTimeText(for: item.createdAt),
                                isScanningOCR: store.ocrScanningEntryID == item.id,
                                isRecentlyCopied: store.lastCopiedEntryID == item.id,
                                onSelect: {
                                    store.copyEntry(item, triggerAutoPaste: false)
                                },
                                onOCR: item.kind == .image ? {
                                    store.recognizeEntry(item)
                                } : nil,
                                onTogglePin: {
                                    store.togglePin(item)
                                },
                                onDelete: {
                                    store.deleteEntry(item)
                                },
                                onHoverChanged: { isHovering in
                                    if isHovering {
                                        store.setHoveredEntry(item)
                                    } else {
                                        store.clearHoveredEntry(item.id)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(10)
            }
        }
        .onAppear {
            store.setUIActive(true)
            store.beginSpacePreviewSession()
        }
        .onDisappear {
            store.endSpacePreviewSession()
            store.dismissOCRResult()
        }
    }
}

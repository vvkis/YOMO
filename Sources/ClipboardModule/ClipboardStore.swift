import Foundation
import AppKit
import SwiftUI
import Carbon
import CryptoKit
import CoreGraphics
import ApplicationServices
import ImageIO
import Vision

public struct ClipboardBarcodeItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let payload: String
    public let symbology: String
    public let isWebURL: Bool

    public init(id: UUID = UUID(), payload: String, symbology: String, isWebURL: Bool) {
        self.id = id
        self.payload = payload
        self.symbology = symbology
        self.isWebURL = isWebURL
    }
}

public struct ClipboardOCRResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let entryID: UUID
    public let sourceLabel: String
    public let rawText: String
    public let mergedText: String
    public let barcodes: [ClipboardBarcodeItem]
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        entryID: UUID,
        sourceLabel: String,
        rawText: String,
        mergedText: String,
        barcodes: [ClipboardBarcodeItem],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.entryID = entryID
        self.sourceLabel = sourceLabel
        self.rawText = rawText
        self.mergedText = mergedText
        self.barcodes = barcodes
        self.errorMessage = errorMessage
    }

    public var hasContent: Bool {
        !rawText.isEmpty || !barcodes.isEmpty
    }
}

public enum ClipboardItemKind: String, Codable, Sendable {
    case text
    case image
}

public enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case text = "文本"
    case image = "图片"
    case pinned = "置顶"

    public var id: String { rawValue }
}

public struct ClipboardEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: ClipboardItemKind
    public let text: String?
    public let imageFileName: String?
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let contentHash: String
    public let sourceAppName: String?
    public let sourceBundleID: String?
    public var createdAt: Date
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        kind: ClipboardItemKind,
        text: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        contentHash: String,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.contentHash = contentHash
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.createdAt = createdAt
        self.isPinned = isPinned
    }

    public var singleLinePreview: String {
        switch kind {
        case .text:
            guard let fullText = text else { return "(空白文本)" }
            // Bound prefix BEFORE normalizing so multi-MB entries never allocate full copies per render
            let sample = fullText.prefix(512)
            let raw = String(sample)
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.count > 120 || fullText.utf8.count > sample.utf8.count {
                return String(raw.prefix(120)) + "…"
            }
            return raw.isEmpty ? "(空白文本)" : raw
        case .image:
            if let w = imageWidth, let h = imageHeight, w > 0, h > 0 {
                return "图片 · \(w) × \(h)"
            }
            return "图片"
        }
    }

    public var characterCount: Int {
        guard let text else { return 0 }
        // Exact grapheme count for normal snippets; O(1) UTF-16 length for huge (>16 KB) pastes
        return text.utf8.count <= 16_384 ? text.count : text.utf16.count
    }
}

/// Zero-permission Carbon global hotkey (⇧⌘V) for popping open Clipboard History from any app.
private final class ClipboardHotKeyManager {
    private static let signature: OSType = 0x594F_4D4F // 'YOMO'
    private static let hotKeyNumber: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        unregister()
    }

    func registerShiftCmdV() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var incomingID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &incomingID
                )
                guard paramStatus == noErr,
                      incomingID.signature == ClipboardHotKeyManager.signature,
                      incomingID.id == ClipboardHotKeyManager.hotKeyNumber else {
                    return OSStatus(eventNotHandledErr)
                }
                let mgr = Unmanaged<ClipboardHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                mgr.onTrigger()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard installStatus == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyNumber)
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if regStatus != noErr {
            unregister()
        }
    }

    func unregister() {
        if let hk = hotKeyRef {
            UnregisterEventHotKey(hk)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}

@MainActor
public final class ClipboardStore: ObservableObject {
    private enum Keys {
        static let maxHistoryCount = "clipboard.maxHistoryCount"
        static let saveImages = "clipboard.saveImages"
        static let globalHotkeyEnabled = "clipboard.globalHotkeyEnabled"
        static let autoPasteEnabled = "clipboard.autoPasteEnabled"
        static let autoCleanupEnabled = "clipboard.autoCleanupEnabled"
        static let autoCleanupHours = "clipboard.autoCleanupHours"
    }

    public static let minAutoCleanupHours = 1
    public static let maxAutoCleanupHours = 720 // 30 days

    /// Standard nspasteboard.org & password-manager markers that must NEVER be recorded
    private static let ignoredPasteboardTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "com.typeit4me.clipping",
        "de.petermaurer.TransientPasteboardType"
    ]

    private static let ignoredSourceBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "org.keepassxc.keepassxc"
    ]

    private nonisolated static let maxTextBytes = 2 * 1024 * 1024        // 2 MB text cap
    private nonisolated static let maxImageBytes = 12 * 1024 * 1024      // 12 MB compressed PNG cap
    private nonisolated static let maxRawTIFFBytes = 64 * 1024 * 1024    // 64 MB uncompressed Retina TIFF cap prior to PNG compression
    private nonisolated static let maxStoredImages = 10                  // Bound disk & memory for unpinned images

    @Published public private(set) var entries: [ClipboardEntry] = []
    @Published public var searchQuery: String = ""
    @Published public var activeFilter: ClipboardFilter = .all
    @Published public var statusMessage: String? = nil
    @Published public private(set) var activeOCRResult: ClipboardOCRResult? = nil
    @Published public private(set) var ocrScanningEntryID: UUID? = nil
    @Published public var ocrMergeLines: Bool = false
    @Published public private(set) var ocrToastMessage: String? = nil
    @Published public private(set) var lastCopiedEntryID: UUID? = nil

    @Published public var maxHistoryCount: Int {
        didSet {
            UserDefaults.standard.set(maxHistoryCount, forKey: Keys.maxHistoryCount)
            trimAndPersist()
        }
    }

    @Published public var saveImages: Bool {
        didSet {
            UserDefaults.standard.set(saveImages, forKey: Keys.saveImages)
        }
    }

    @Published public var globalHotkeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalHotkeyEnabled, forKey: Keys.globalHotkeyEnabled)
            syncHotKeyRegistration()
        }
    }

    @Published public var autoPasteEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoPasteEnabled, forKey: Keys.autoPasteEnabled)
        }
    }

    @Published public var autoCleanupEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCleanupEnabled, forKey: Keys.autoCleanupEnabled)
            if autoCleanupEnabled {
                trimAndPersist()
            }
        }
    }

    @Published public var autoCleanupHours: Int {
        didSet {
            let clamped = min(max(autoCleanupHours, Self.minAutoCleanupHours), Self.maxAutoCleanupHours)
            if clamped != autoCleanupHours {
                autoCleanupHours = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.autoCleanupHours)
            if autoCleanupEnabled {
                trimAndPersist()
            }
        }
    }

    /// Invoked when the user presses the global ⇧⌘V shortcut anywhere on macOS
    public var onGlobalHotKeyPressed: (() -> Void)?

    /// Internal snapshot updated even when UI is hidden (zero SwiftUI diffs while idle)
    private var latestEntries: [ClipboardEntry] = []
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastAutoCleanupCheckAt: Date = Date()
    private var timer: Timer?
    private var isModuleEnabled: Bool = true
    private var isUIActive: Bool = false
    private var isScreenAsleep: Bool = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var hotKeyManager: ClipboardHotKeyManager?
    private var ocrToastClearWorkItem: DispatchWorkItem?
    private var copyFeedbackClearWorkItem: DispatchWorkItem?
    private var copyToastHUD: ClipboardCopyToastHUD?
    private var quickPreviewPanel: ClipboardQuickPreviewPanel?
    private var spaceKeyMonitor: Any?
    private var previewResignObserver: NSObjectProtocol?
    private var previewSessionCount: Int = 0
    private var hoveredEntry: ClipboardEntry?
    private var isSpacePreviewHeld: Bool = false
    private var previewLoadGeneration: UInt64 = 0
    private var captureGeneration: UInt64 = 0
    private var lazyImagePasteboardProvider: LazyImagePasteboardProvider?
    private let ioQueue = DispatchQueue(label: "com.yomo.clipboard.io", qos: .utility)
    private let ocrQueue = DispatchQueue(label: "com.yomo.clipboard.ocr", qos: .userInitiated)
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let appIconCache = NSCache<NSString, NSImage>()
    private var missingAppIconBundleIDs: Set<String> = []

    private let storageDirURL: URL
    private let historyFileURL: URL
    private let imagesDirURL: URL

    public init() {
        let ud = UserDefaults.standard
        let savedMax = ud.integer(forKey: Keys.maxHistoryCount)
        self.maxHistoryCount = [30, 50, 100].contains(savedMax) ? savedMax : 50
        self.saveImages = ud.object(forKey: Keys.saveImages) as? Bool ?? true
        self.globalHotkeyEnabled = ud.object(forKey: Keys.globalHotkeyEnabled) as? Bool ?? true
        self.autoPasteEnabled = ud.object(forKey: Keys.autoPasteEnabled) as? Bool ?? false
        self.autoCleanupEnabled = ud.object(forKey: Keys.autoCleanupEnabled) as? Bool ?? false
        let savedHours = ud.integer(forKey: Keys.autoCleanupHours)
        self.autoCleanupHours = (Self.minAutoCleanupHours...Self.maxAutoCleanupHours).contains(savedHours) ? savedHours : 24

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.storageDirURL = appSupport.appendingPathComponent("YOMO", isDirectory: true)
        self.historyFileURL = storageDirURL.appendingPathComponent("clipboard-history.json")
        self.imagesDirURL = storageDirURL.appendingPathComponent("clipboard-images", isDirectory: true)

        thumbnailCache.countLimit = 24
        thumbnailCache.totalCostLimit = 4 * 1024 * 1024 // 4 MB cap for 128px thumbnails
        appIconCache.countLimit = 32

        loadPersistedHistory()
        setupSleepWakeObservers()
        setupHotKeyManager()
        lastChangeCount = NSPasteboard.general.changeCount
    }

    deinit {
        timer?.invalidate()
        hotKeyManager?.unregister()
        if let monitor = spaceKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let obs = previewResignObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        let nc = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            nc.removeObserver(obs)
        }
    }

    // MARK: - Lifecycle & Visibility Gating

    public func syncWithModuleEnabled(_ enabled: Bool) {
        isModuleEnabled = enabled
        if enabled {
            lastChangeCount = NSPasteboard.general.changeCount
            purgeExpiredIfDue(force: true)
            startMonitoringTimer()
            syncHotKeyRegistration()
        } else {
            captureGeneration &+= 1
            stopMonitoringTimer()
            hotKeyManager?.unregister()
        }
    }

    public func setUIActive(_ active: Bool) {
        isUIActive = active
        if active {
            purgeExpiredIfDue(force: true)
            checkPasteboardNow()
            publishToUI()
        } else {
            hideQuickPreview()
            ocrToastClearWorkItem?.cancel()
            ocrScanningEntryID = nil
            activeOCRResult = nil
            ocrToastMessage = nil
        }
    }

    // MARK: - Hold Spacebar Image & Text Quick Preview (Zero Idle Cost)

    public func beginSpacePreviewSession() {
        previewSessionCount += 1
        guard previewSessionCount == 1 else { return }

        if spaceKeyMonitor == nil {
            spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self else { return event }
                return self.handleLocalPreviewKeyEvent(event)
            }
        }
        if previewResignObserver == nil {
            previewResignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.hideQuickPreview()
                }
            }
        }
    }

    public func endSpacePreviewSession() {
        previewSessionCount = max(0, previewSessionCount - 1)
        guard previewSessionCount == 0 else { return }
        hoveredEntry = nil
        hideQuickPreview()
        if let monitor = spaceKeyMonitor {
            NSEvent.removeMonitor(monitor)
            spaceKeyMonitor = nil
        }
        if let obs = previewResignObserver {
            NotificationCenter.default.removeObserver(obs)
            previewResignObserver = nil
        }
    }

    public func setHoveredEntry(_ entry: ClipboardEntry) {
        hoveredEntry = entry
        if isSpacePreviewHeld {
            showQuickPreview(for: entry)
        }
    }

    public func clearHoveredEntry(_ id: UUID) {
        if hoveredEntry?.id == id {
            hoveredEntry = nil
            if isSpacePreviewHeld {
                hideQuickPreview(keepSpaceHeldState: true)
            }
        }
    }

    private func handleLocalPreviewKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Never intercept Spacebar while the user is typing inside the search TextField
        if NSApp.keyWindow?.firstResponder is NSTextView {
            return event
        }

        if event.keyCode == UInt16(kVK_Escape), isSpacePreviewHeld {
            hideQuickPreview()
            return nil
        }

        guard event.keyCode == UInt16(kVK_Space) else {
            return event
        }

        switch event.type {
        case .keyDown:
            let hasModifiers = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            guard !hasModifiers, let hovered = hoveredEntry else {
                return event
            }
            if !event.isARepeat && !isSpacePreviewHeld {
                isSpacePreviewHeld = true
                showQuickPreview(for: hovered)
            }
            return nil

        case .keyUp:
            if isSpacePreviewHeld {
                hideQuickPreview()
                return nil
            }
            return event

        default:
            return event
        }
    }

    private func showQuickPreview(for entry: ClipboardEntry) {
        previewLoadGeneration &+= 1
        let gen = previewLoadGeneration
        let anchorWindowFrame = NSApp.keyWindow?.frame
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) })
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let scale = targetScreen?.backingScaleFactor ?? 2.0
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        switch entry.kind {
        case .text:
            guard let rawText = entry.text else { return }
            let maxPreviewChars = 24_000
            let displayText: String
            if rawText.count > maxPreviewChars {
                displayText = String(rawText.prefix(maxPreviewChars)) + "\n\n…（全文共 \(entry.characterCount) 字，已省略超长尾部）"
            } else {
                displayText = rawText
            }
            var parts: [String] = ["\(entry.characterCount) 字"]
            if let app = entry.sourceAppName, !app.isEmpty {
                parts.append(app)
            }
            parts.append("松开空格关闭")
            let caption = parts.joined(separator: " · ")

            if quickPreviewPanel == nil {
                quickPreviewPanel = ClipboardQuickPreviewPanel()
            }
            quickPreviewPanel?.showText(
                displayText,
                caption: caption,
                anchorWindowFrame: anchorWindowFrame,
                visibleFrame: visibleFrame
            )

        case .image:
            guard let fileName = entry.imageFileName else { return }
            let fileURL = imagesDirURL.appendingPathComponent(fileName)
            let maxDisplayW = min(760.0, visibleFrame.width * 0.56)
            let maxDisplayH = min(660.0, visibleFrame.height * 0.72)
            let maxPixel = Int(ceil(max(maxDisplayW, maxDisplayH) * scale))

            var parts: [String] = []
            if let w = entry.imageWidth, let h = entry.imageHeight, w > 0, h > 0 {
                parts.append("\(w) × \(h)")
            }
            if let app = entry.sourceAppName, !app.isEmpty {
                parts.append(app)
            }
            parts.append("松开空格关闭")
            let caption = parts.joined(separator: " · ")

            ioQueue.async { [weak self] in
                guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return }
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let cgImg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return }
                let previewImg = NSImage(
                    cgImage: cgImg,
                    size: NSSize(width: CGFloat(cgImg.width) / scale, height: CGFloat(cgImg.height) / scale)
                )
                let logicalSize = previewImg.size

                Task { @MainActor [weak self] in
                    guard let self, self.isSpacePreviewHeld, self.previewLoadGeneration == gen else { return }
                    if self.quickPreviewPanel == nil {
                        self.quickPreviewPanel = ClipboardQuickPreviewPanel()
                    }
                    self.quickPreviewPanel?.showImage(
                        previewImg,
                        logicalSize: logicalSize,
                        caption: caption,
                        anchorWindowFrame: anchorWindowFrame,
                        visibleFrame: visibleFrame
                    )
                }
            }
        }
    }

    private func hideQuickPreview(keepSpaceHeldState: Bool = false) {
        if !keepSpaceHeldState {
            isSpacePreviewHeld = false
        }
        previewLoadGeneration &+= 1
        quickPreviewPanel?.hideSmoothly()
    }

    public func openStorageFolder() {
        try? FileManager.default.createDirectory(at: storageDirURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(storageDirURL)
    }

    public func stop() {
        stopMonitoringTimer()
        hotKeyManager?.unregister()
    }

    // MARK: - Computed Properties for Views

    public var filteredEntries: [ClipboardEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let qLower = q.lowercased()
        return entries.filter { item in
            switch activeFilter {
            case .all: break
            case .text: if item.kind != .text { return false }
            case .image: if item.kind != .image { return false }
            case .pinned: if !item.isPinned { return false }
            }
            if q.isEmpty { return true }
            if let text = item.text, text.range(of: q, options: .caseInsensitive) != nil { return true }
            if let app = item.sourceAppName, app.range(of: q, options: .caseInsensitive) != nil { return true }
            if item.kind == .image && ("图片".contains(qLower) || "image".contains(qLower)) { return true }
            return false
        }
    }

    public var latestPreviewSubtitle: String {
        guard let first = entries.first ?? latestEntries.first else {
            return "暂无记录 · ⇧⌘V 唤出"
        }
        return first.singleLinePreview
    }

    public var totalCount: Int {
        entries.count
    }

    public var hasUnpinnedItems: Bool {
        entries.contains(where: { !$0.isPinned })
    }

    // MARK: - User Actions

    /// Copies the entry to the system pasteboard.
    /// Returns `true` when auto-paste (⌘V) was triggered so callers can dismiss the popover if needed.
    @discardableResult
    public func copyEntry(_ entry: ClipboardEntry, triggerAutoPaste: Bool = true) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch entry.kind {
        case .text:
            guard let text = entry.text else { return false }
            pb.setString(text, forType: .string)
        case .image:
            guard let fileName = entry.imageFileName else { return false }
            let fileURL = imagesDirURL.appendingPathComponent(fileName)
            guard let pngData = try? Data(contentsOf: fileURL) else {
                statusMessage = "图片文件已丢失"
                showCopyHUD(title: "复制失败", detail: "图片文件已丢失", isError: true)
                return false
            }
            // Write PNG eagerly and supply uncompressed TIFF lazily ONLY if a pasting consumer requests it
            let provider = LazyImagePasteboardProvider(pngData: pngData)
            lazyImagePasteboardProvider = provider
            let pbItem = NSPasteboardItem()
            pbItem.setData(pngData, forType: .png)
            pbItem.setDataProvider(provider, forTypes: [.tiff])
            pb.writeObjects([pbItem])
        }

        // Prevent our own write from being re-captured on the next timer tick
        lastChangeCount = pb.changeCount

        let willAutoPaste = triggerAutoPaste && autoPasteEnabled && AXIsProcessTrusted()
        let preview = entry.singleLinePreview
        let shortDetail = preview.count > 24 ? String(preview.prefix(24)) + "…" : preview
        let hudTitle = willAutoPaste ? "已复制并粘贴" : (entry.kind == .image ? "已复制图片" : "已复制文本")
        markRecentlyCopied(entry.id)
        showCopyHUD(title: hudTitle, detail: shortDetail, isError: false)

        if willAutoPaste {
            // Wait slightly past GlassPopoverPanel's 0.12s dismiss animation so ⌘V lands in the target app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                Self.sendCommandVKeystroke()
            }
        }
        return willAutoPaste
    }

    private func markRecentlyCopied(_ id: UUID) {
        copyFeedbackClearWorkItem?.cancel()
        lastCopiedEntryID = id
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                if self?.lastCopiedEntryID == id {
                    self?.lastCopiedEntryID = nil
                }
            }
        }
        copyFeedbackClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func showCopyHUD(title: String, detail: String, isError: Bool) {
        if copyToastHUD == nil {
            copyToastHUD = ClipboardCopyToastHUD()
        }
        copyToastHUD?.show(title: title, detail: detail, isError: isError)
    }

    public func togglePin(_ entry: ClipboardEntry) {
        guard let idx = latestEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        latestEntries[idx].isPinned.toggle()
        sortEntriesInPlace(&latestEntries)
        publishToUI()
        persistHistoryAsync()
    }

    public func deleteEntry(_ entry: ClipboardEntry) {
        latestEntries.removeAll { $0.id == entry.id }
        if activeOCRResult?.entryID == entry.id || ocrScanningEntryID == entry.id {
            dismissOCRResult()
        }
        if let fileName = entry.imageFileName {
            removeImageFileAsync(fileName)
        }
        publishToUI()
        persistHistoryAsync()
    }

    public func clearUnpinned() {
        let removedIDs = Set(latestEntries.filter { !$0.isPinned }.map(\.id))
        let removedImages = latestEntries.filter { !$0.isPinned }.compactMap(\.imageFileName)
        latestEntries.removeAll { !$0.isPinned }
        if (activeOCRResult.map { removedIDs.contains($0.entryID) } ?? false)
            || (ocrScanningEntryID.map { removedIDs.contains($0) } ?? false) {
            dismissOCRResult()
        }
        for fileName in removedImages {
            removeImageFileAsync(fileName)
        }
        publishToUI()
        persistHistoryAsync()
    }

    public func clearAll() {
        captureGeneration &+= 1
        let removedImages = latestEntries.compactMap(\.imageFileName)
        latestEntries.removeAll()
        dismissOCRResult()
        for fileName in removedImages {
            removeImageFileAsync(fileName)
        }
        publishToUI()
        persistHistoryAsync()
    }

    // MARK: - On-Demand Vision OCR & Barcode Scanning

    public func recognizeEntry(_ entry: ClipboardEntry) {
        guard entry.kind == .image, let fileName = entry.imageFileName else { return }
        let fileURL = imagesDirURL.appendingPathComponent(fileName)
        let entryID = entry.id
        let sourceLabel = entry.singleLinePreview

        ocrToastClearWorkItem?.cancel()
        ocrToastMessage = nil
        ocrScanningEntryID = entryID

        // Barrier through `ioQueue` first so a freshly-captured PNG finishes writing to disk before Vision reads it
        let scanQueue = ocrQueue
        ioQueue.async { [weak self] in
            scanQueue.async { [weak self] in
                let result = Self.performVisionScan(fileURL: fileURL, entryID: entryID, sourceLabel: sourceLabel)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.ocrScanningEntryID == entryID else { return }
                    self.ocrScanningEntryID = nil
                    self.activeOCRResult = result
                }
            }
        }
    }

    public func dismissOCRResult() {
        ocrToastClearWorkItem?.cancel()
        ocrScanningEntryID = nil
        activeOCRResult = nil
        ocrToastMessage = nil
    }

    public func entry(for id: UUID) -> ClipboardEntry? {
        latestEntries.first { $0.id == id } ?? entries.first { $0.id == id }
    }

    /// Writes OCR/barcode text to the system pasteboard WITHOUT adding a duplicate entry
    /// into clipboard history and WITHOUT closing or stealing focus from the popover.
    public func copyOCRText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount

        showOCRToast("已复制到剪贴板")
    }

    public func openBarcodeURL(_ payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func showOCRToast(_ message: String) {
        ocrToastClearWorkItem?.cancel()
        ocrToastMessage = message
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.ocrToastMessage = nil
            }
        }
        ocrToastClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private nonisolated static func performVisionScan(
        fileURL: URL,
        entryID: UUID,
        sourceLabel: String
    ) -> ClipboardOCRResult {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return ClipboardOCRResult(
                entryID: entryID,
                sourceLabel: sourceLabel,
                rawText: "",
                mergedText: "",
                barcodes: [],
                errorMessage: "图片文件不可读或已清理"
            )
        }

        let orientation: CGImagePropertyOrientation = {
            guard let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let raw = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value,
                  let parsed = CGImagePropertyOrientation(rawValue: raw) else {
                return .up
            }
            return parsed
        }()

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true

        let barcodeRequest = VNDetectBarcodesRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([textRequest, barcodeRequest])
        } catch {
            return ClipboardOCRResult(
                entryID: entryID,
                sourceLabel: sourceLabel,
                rawText: "",
                mergedText: "",
                barcodes: [],
                errorMessage: "识别失败：\(error.localizedDescription)"
            )
        }

        // Strictly transitive top-to-bottom sort (+Y is up in Vision normalized coords), then cluster
        // into visual rows and sort each row strictly left-to-right to avoid Introsort non-transitivity crashes.
        let ySorted = (textRequest.results ?? []).sorted { lhs, rhs in
            if lhs.boundingBox.midY != rhs.boundingBox.midY {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var visualRows: [(anchorMidY: CGFloat, avgHeight: CGFloat, items: [VNRecognizedTextObservation])] = []
        for obs in ySorted {
            let box = obs.boundingBox
            if let lastIdx = visualRows.indices.last {
                let tol = max(0.01, (visualRows[lastIdx].avgHeight + box.height) * 0.5) * 0.55
                if abs(visualRows[lastIdx].anchorMidY - box.midY) <= tol {
                    let count = CGFloat(visualRows[lastIdx].items.count)
                    visualRows[lastIdx].anchorMidY = (visualRows[lastIdx].anchorMidY * count + box.midY) / (count + 1)
                    visualRows[lastIdx].avgHeight = (visualRows[lastIdx].avgHeight * count + box.height) / (count + 1)
                    visualRows[lastIdx].items.append(obs)
                    continue
                }
            }
            visualRows.append((anchorMidY: box.midY, avgHeight: box.height, items: [obs]))
        }

        let textLines: [String] = visualRows.compactMap { row in
            let segments = row.items
                .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !segments.isEmpty else { return nil }
            return segments.joined(separator: " ")
        }
        let rawText = textLines.joined(separator: "\n")
        let mergedText = mergeLinesSmartly(textLines)

        var seenPayloads = Set<String>()
        var barcodes: [ClipboardBarcodeItem] = []
        for obs in (barcodeRequest.results ?? []) {
            guard let payload = obs.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !payload.isEmpty,
                  seenPayloads.insert(payload).inserted else {
                continue
            }
            let isWeb: Bool = {
                guard let url = URL(string: payload),
                      let scheme = url.scheme?.lowercased(),
                      (scheme == "http" || scheme == "https"),
                      url.host != nil else { return false }
                return true
            }()
            let label = obs.symbology == .qr ? "二维码" : "条形码"
            barcodes.append(ClipboardBarcodeItem(payload: payload, symbology: label, isWebURL: isWeb))
        }

        return ClipboardOCRResult(
            entryID: entryID,
            sourceLabel: sourceLabel,
            rawText: rawText,
            mergedText: mergedText,
            barcodes: barcodes
        )
    }

    private nonisolated static func mergeLinesSmartly(_ lines: [String]) -> String {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        var result = cleaned[0]
        for next in cleaned.dropFirst() {
            if let lastScalar = result.unicodeScalars.last,
               let firstScalar = next.unicodeScalars.first,
               lastScalar.isASCII, firstScalar.isASCII {
                result += " " + next
            } else {
                result += next
            }
        }
        return result
    }

    public func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let fileName = entry.imageFileName else { return nil }
        let key = fileName as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        let url = imagesDirURL.appendingPathComponent(fileName)
        // Decode downsampled 128px thumbnail via ImageIO instead of loading full multi-megapixel Retina bitmaps
        let img: NSImage?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceShouldCacheImmediately: true
            ]
            if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                img = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
            } else {
                img = nil
            }
        } else {
            img = nil
        }
        guard let img else { return nil }
        let cost = max(1, Int(img.size.width * img.size.height * 4))
        thumbnailCache.setObject(img, forKey: key, cost: cost)
        return img
    }

    public func sourceIcon(for entry: ClipboardEntry) -> NSImage? {
        guard let bundleID = entry.sourceBundleID, !bundleID.isEmpty else { return nil }
        let key = bundleID as NSString
        if let cached = appIconCache.object(forKey: key) {
            return cached
        }
        if missingAppIconBundleIDs.contains(bundleID) {
            return nil
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missingAppIconBundleIDs.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        appIconCache.setObject(icon, forKey: key)
        return icon
    }

    public func relativeTimeText(for date: Date) -> String {
        let sec = max(0, Int(Date().timeIntervalSince(date)))
        if sec < 60 { return "刚刚" }
        if sec < 3600 { return "\(sec / 60) 分钟前" }
        if sec < 86400 { return "\(sec / 3600) 小时前" }
        return "\(sec / 86400) 天前"
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public var hasAccessibilityForAutoPaste: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Pasteboard Capture (Privacy-Aware & Low-Overhead)

    private func setupHotKeyManager() {
        let mgr = ClipboardHotKeyManager { [weak self] in
            Task { @MainActor [weak self] in
                self?.onGlobalHotKeyPressed?()
            }
        }
        self.hotKeyManager = mgr
        syncHotKeyRegistration()
    }

    private func syncHotKeyRegistration() {
        if isModuleEnabled && globalHotkeyEnabled {
            hotKeyManager?.registerShiftCmdV()
        } else {
            hotKeyManager?.unregister()
        }
    }

    private func setupSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isScreenAsleep = true
                    self?.stopMonitoringTimer()
                }
            }
            workspaceObservers.append(obs)
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isScreenAsleep = false
                    if self.isModuleEnabled {
                        self.purgeExpiredIfDue(force: true)
                        self.startMonitoringTimer()
                    }
                }
            }
            workspaceObservers.append(obs)
        }
    }

    private func startMonitoringTimer() {
        stopMonitoringTimer()
        guard isModuleEnabled && !isScreenAsleep else { return }
        let newTimer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboardNow()
            }
        }
        newTimer.tolerance = 0.40
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopMonitoringTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboardNow() {
        guard isModuleEnabled else { return }
        purgeExpiredIfDue(force: false)
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // 1. Privacy check: skip concealed / transient / password manager clipboard items
        let types = Set((pb.types ?? []).map(\.rawValue))
        if !types.isDisjoint(with: Self.ignoredPasteboardTypes) {
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        if let bundleID, Self.ignoredSourceBundleIDs.contains(bundleID) {
            return
        }
        let appName = frontApp?.localizedName

        // 2. Capture Text (prefer string over image when both exist, e.g. rich text from browsers/Keynote)
        if let str = pb.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, str.utf8.count <= Self.maxTextBytes else { return }
            let gen = captureGeneration
            ioQueue.async { [weak self] in
                let hash = Self.sha256Hex(Data(str.utf8))
                let entry = ClipboardEntry(
                    kind: .text,
                    text: str,
                    contentHash: hash,
                    sourceAppName: appName,
                    sourceBundleID: bundleID
                )
                DispatchQueue.main.async {
                    guard let self, self.isModuleEnabled, self.captureGeneration == gen else { return }
                    self.insertOrBumpEntry(entry)
                }
            }
            return
        }

        // 3. Capture Image (screenshots / copied images) when enabled — decode/encode, hash & disk write 100% off main thread
        if saveImages {
            let directPNG = pb.data(forType: .png)
            let rawTIFF = (directPNG == nil) ? pb.data(forType: .tiff) : nil
            let isAlreadyPNG = (directPNG != nil)
            let rawCap = isAlreadyPNG ? Self.maxImageBytes : Self.maxRawTIFFBytes
            guard let rawData = directPNG ?? rawTIFF, rawData.count <= rawCap else {
                return
            }
            let dirURL = imagesDirURL
            let gen = captureGeneration

            ioQueue.async { [weak self] in
                guard let rep = NSBitmapImageRep(data: rawData) else { return }
                let pngData: Data
                if isAlreadyPNG {
                    pngData = rawData
                } else {
                    guard let encoded = rep.representation(using: .png, properties: [:]) else { return }
                    pngData = encoded
                }
                guard pngData.count <= Self.maxImageBytes else { return }

                let hash = Self.sha256Hex(pngData)
                let pixelW = rep.pixelsWide
                let pixelH = rep.pixelsHigh
                let fileName = "\(UUID().uuidString).png"
                let targetURL = dirURL.appendingPathComponent(fileName)

                // Write PNG atomically with 0600 permissions BEFORE publishing entry to UI
                guard Self.writeSecureFile(data: pngData, to: targetURL, directory: dirURL) else {
                    return
                }

                DispatchQueue.main.async {
                    guard let self else {
                        try? FileManager.default.removeItem(at: targetURL)
                        return
                    }
                    guard self.isModuleEnabled, self.captureGeneration == gen else {
                        self.removeImageFileAsync(fileName)
                        return
                    }
                    if let existingIdx = self.latestEntries.firstIndex(where: { $0.kind == .image && $0.contentHash == hash }) {
                        // Duplicate image already stored: drop the newly written file and bump existing entry
                        self.removeImageFileAsync(fileName)
                        var bumped = self.latestEntries.remove(at: existingIdx)
                        bumped.createdAt = Date()
                        self.latestEntries.insert(bumped, at: 0)
                        self.sortEntriesInPlace(&self.latestEntries)
                        if self.isUIActive { self.publishToUI() }
                        self.persistHistoryAsync()
                        return
                    }

                    let entry = ClipboardEntry(
                        kind: .image,
                        imageFileName: fileName,
                        imageWidth: pixelW,
                        imageHeight: pixelH,
                        contentHash: hash,
                        sourceAppName: appName,
                        sourceBundleID: bundleID
                    )
                    self.insertOrBumpEntry(entry)
                }
            }
        }
    }

    private func insertOrBumpEntry(_ incoming: ClipboardEntry) {
        if let existingIdx = latestEntries.firstIndex(where: { $0.kind == incoming.kind && $0.contentHash == incoming.contentHash }) {
            var bumped = latestEntries.remove(at: existingIdx)
            bumped.createdAt = Date()
            latestEntries.insert(bumped, at: 0)
        } else {
            latestEntries.insert(incoming, at: 0)
        }

        sortEntriesInPlace(&latestEntries)
        enforceRetentionLimits()

        if isUIActive {
            publishToUI()
        }
        persistHistoryAsync()
    }

    private func trimAndPersist() {
        let now = Date()
        lastAutoCleanupCheckAt = now
        let didChange = enforceRetentionLimits(now: now)
        if didChange {
            if isUIActive {
                publishToUI()
            }
            persistHistoryAsync()
        }
    }

    private func purgeExpiredIfDue(force: Bool) {
        guard autoCleanupEnabled else { return }
        let now = Date()
        if !force && now.timeIntervalSince(lastAutoCleanupCheckAt) < 300 {
            return
        }
        lastAutoCleanupCheckAt = now
        if enforceRetentionLimits(now: now) {
            if isUIActive {
                publishToUI()
            }
            persistHistoryAsync()
        }
    }

    @discardableResult
    private func enforceRetentionLimits(now: Date = Date()) -> Bool {
        let previousIDs = latestEntries.map(\.id)
        var pinned = latestEntries.filter(\.isPinned)
        var unpinned = latestEntries.filter { !$0.isPinned }

        // 1. Optional age-based auto-cleanup for unpinned items (pinned items are preserved)
        if autoCleanupEnabled {
            let maxAgeSeconds = TimeInterval(max(Self.minAutoCleanupHours, autoCleanupHours)) * 3600.0
            var freshUnpinned: [ClipboardEntry] = []
            freshUnpinned.reserveCapacity(unpinned.count)
            for item in unpinned {
                if now.timeIntervalSince(item.createdAt) >= maxAgeSeconds {
                    if let fileName = item.imageFileName {
                        removeImageFileAsync(fileName)
                    }
                } else {
                    freshUnpinned.append(item)
                }
            }
            unpinned = freshUnpinned
        }

        // 2. Cap unpinned count
        let maxUnpinned = max(1, maxHistoryCount)
        if unpinned.count > maxUnpinned {
            let dropped = unpinned.suffix(from: maxUnpinned)
            for item in dropped {
                if let fileName = item.imageFileName {
                    removeImageFileAsync(fileName)
                }
            }
            unpinned = Array(unpinned.prefix(maxUnpinned))
        }

        // 3. Cap total stored unpinned images to prevent unbounded disk/RAM growth (pinned images do not consume unpinned quota)
        var unpinnedImageCount = 0
        var filteredUnpinned: [ClipboardEntry] = []
        filteredUnpinned.reserveCapacity(unpinned.count)
        for item in unpinned {
            if item.kind == .image {
                if unpinnedImageCount < Self.maxStoredImages {
                    unpinnedImageCount += 1
                    filteredUnpinned.append(item)
                } else if let fileName = item.imageFileName {
                    removeImageFileAsync(fileName)
                }
            } else {
                filteredUnpinned.append(item)
            }
        }

        pinned.sort { $0.createdAt > $1.createdAt }
        filteredUnpinned.sort { $0.createdAt > $1.createdAt }
        let updated = pinned + filteredUnpinned
        let updatedIDs = Set(updated.map(\.id))
        if (activeOCRResult.map { !updatedIDs.contains($0.entryID) } ?? false)
            || (ocrScanningEntryID.map { !updatedIDs.contains($0) } ?? false) {
            dismissOCRResult()
        }
        latestEntries = updated
        return updated.map(\.id) != previousIDs
    }

    private func sortEntriesInPlace(_ list: inout [ClipboardEntry]) {
        list.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }
    }

    private func publishToUI() {
        entries = latestEntries
    }

    // MARK: - Local Encrypted-Permission Persistence (0600)

    private func loadPersistedHistory() {
        guard let data = try? Data(contentsOf: historyFileURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else {
            return
        }
        latestEntries = decoded
        sortEntriesInPlace(&latestEntries)
        let didPrune = enforceRetentionLimits()
        entries = latestEntries
        if didPrune {
            persistHistoryAsync()
        }
    }

    private func persistHistoryAsync() {
        let snapshot = latestEntries
        let dir = storageDirURL
        let file = historyFileURL
        ioQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                _ = Self.writeSecureFile(data: data, to: file, directory: dir)
            }
        }
    }

    /// Creates parent directories with `0700` permissions and atomically writes a `0600` file
    /// without exposing a temporary world-readable (`0644`) window.
    private nonisolated static func writeSecureFile(data: Data, to destination: URL, directory: URL) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let tmpURL = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
            guard fm.createFile(atPath: tmpURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                return false
            }
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: tmpURL)
            } else {
                try fm.moveItem(at: tmpURL, to: destination)
            }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return true
        } catch {
            return false
        }
    }

    private func removeImageFileAsync(_ fileName: String) {
        thumbnailCache.removeObject(forKey: fileName as NSString)
        let url = imagesDirURL.appendingPathComponent(fileName)
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sendCommandVKeystroke() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

/// Non-activating, click-through floating HUD toast confirming clipboard copies even after
/// the menu bar popover closes. Always appears on the active cursor screen for dual-display setups.
@MainActor
private final class ClipboardCopyToastHUD: NSPanel {
    private final class Model: ObservableObject {
        @Published var title: String = "已复制"
        @Published var detail: String = ""
        @Published var isError: Bool = false
    }

    private let model = Model()
    private var dismissWorkItem: DispatchWorkItem?
    private var showGeneration: UInt64 = 0
    private let panelWidth: CGFloat = 258
    private let panelHeight: CGFloat = 46

    init() {
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
        ignoresMouseEvents = true

        let host = NSHostingView(rootView: ClipboardCopyToastView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        host.autoresizingMask = [.width, .height]
        self.contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(title: String, detail: String, isError: Bool) {
        dismissWorkItem?.cancel()
        showGeneration &+= 1
        let gen = showGeneration

        model.title = title
        model.detail = detail
        model.isError = isError

        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen = targetScreen {
            let vf = screen.visibleFrame
            let x = round(vf.midX - panelWidth / 2.0)
            let y = round(vf.minY + 64.0)
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
        }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.showGeneration == gen else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self.animator().alphaValue = 0.0
                }, completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, self.showGeneration == gen else { return }
                        self.orderOut(nil)
                        self.alphaValue = 1.0
                    }
                })
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }

    private struct ClipboardCopyToastView: View {
        @ObservedObject var model: Model

        var body: some View {
            HStack(spacing: 9) {
                Image(systemName: model.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.isError ? Color.orange : Color(red: 0.12, green: 0.82, blue: 0.52))

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    if !model.detail.isEmpty {
                        Text(model.detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(Color(nsColor: NSColor(white: 0.11, alpha: 0.90)))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.75)
                    )
            )
        }
    }
}

/// Supplies uncompressed TIFF on demand ONLY when a paste consumer explicitly requests `.tiff`,
/// avoiding synchronous 30–60 MB TIFF encoding on the main thread during every image copy.
private final class LazyImagePasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    private let pngData: Data

    init(pngData: Data) {
        self.pngData = pngData
        super.init()
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff else { return }
        if let img = NSImage(data: pngData), let tiff = img.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
    }
}

/// Non-activating, click-through floating preview panel triggered while holding Spacebar
/// over ANY clipboard entry (image OR full text). Immediately frees image/text payload on hide.
@MainActor
private final class ClipboardQuickPreviewPanel: NSPanel {
    private final class Model: ObservableObject {
        @Published var image: NSImage? = nil
        @Published var text: String? = nil
        @Published var caption: String = ""
    }

    private let model = Model()
    private var animationGeneration: UInt64 = 0
    private let footerHeight: CGFloat = 34
    private let contentPadding: CGFloat = 10

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
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
        ignoresMouseEvents = true

        let host = NSHostingView(rootView: PreviewContentView(model: model, padding: contentPadding, footerHeight: footerHeight))
        host.autoresizingMask = [.width, .height]
        self.contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showImage(
        _ image: NSImage,
        logicalSize: NSSize,
        caption: String,
        anchorWindowFrame: NSRect?,
        visibleFrame: NSRect
    ) {
        animationGeneration &+= 1
        model.text = nil
        model.image = image
        model.caption = caption

        let maxW = min(760.0, visibleFrame.width * 0.56)
        let maxH = min(660.0, visibleFrame.height * 0.72)
        let imgW = max(1.0, logicalSize.width)
        let imgH = max(1.0, logicalSize.height)

        let fitScale = min(1.0, min((maxW - contentPadding * 2) / imgW, (maxH - contentPadding * 2 - footerHeight) / imgH))
        let drawW = max(220.0, round(imgW * fitScale))
        let drawH = max(140.0, round(imgH * fitScale))
        let panelW = min(maxW, drawW + contentPadding * 2)
        let panelH = min(maxH, drawH + contentPadding * 2 + footerHeight)

        presentPanel(width: panelW, height: panelH, anchorWindowFrame: anchorWindowFrame, visibleFrame: visibleFrame)
    }

    func showText(
        _ text: String,
        caption: String,
        anchorWindowFrame: NSRect?,
        visibleFrame: NSRect
    ) {
        animationGeneration &+= 1
        model.image = nil
        model.text = text
        model.caption = caption

        let maxW = min(540.0, visibleFrame.width * 0.44)
        let maxH = min(560.0, visibleFrame.height * 0.68)
        let charCount = text.count
        let panelW: CGFloat = charCount < 80 ? 340 : (charCount < 300 ? 430 : maxW)

        // Measure actual wrapped text height using AppKit NSString boundingRect for snug fit
        let textInsetX: CGFloat = contentPadding * 2 + 24
        let font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3.5
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: panelW - textInsetX, height: maxH),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: para]
        )
        let neededH = ceil(measured.height) + contentPadding * 2 + 24 + footerHeight
        let panelH = min(maxH, max(126.0, neededH))

        presentPanel(width: panelW, height: panelH, anchorWindowFrame: anchorWindowFrame, visibleFrame: visibleFrame)
    }

    private func presentPanel(
        width panelW: CGFloat,
        height panelH: CGFloat,
        anchorWindowFrame: NSRect?,
        visibleFrame: NSRect
    ) {
        // Position neatly beside the clipboard popover/window so it never blocks the hover list
        let gap: CGFloat = 14
        let originX: CGFloat
        let originY: CGFloat

        if let anchor = anchorWindowFrame {
            if anchor.minX - gap - panelW >= visibleFrame.minX + 12 {
                originX = round(anchor.minX - gap - panelW)
            } else if anchor.maxX + gap + panelW <= visibleFrame.maxX - 12 {
                originX = round(anchor.maxX + gap)
            } else {
                originX = round(visibleFrame.midX - panelW / 2.0)
            }
            let idealY = anchor.maxY - panelH - 12
            originY = round(min(visibleFrame.maxY - panelH - 12, max(visibleFrame.minY + 16, idealY)))
        } else {
            originX = round(visibleFrame.midX - panelW / 2.0)
            originY = round(visibleFrame.midY - panelH / 2.0)
        }

        let targetFrame = NSRect(x: originX, y: originY, width: panelW, height: panelH)
        let wasVisible = isVisible
        setFrame(targetFrame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: targetFrame.size)

        if !wasVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1.0
            }
        } else {
            alphaValue = 1.0
            orderFrontRegardless()
        }
    }

    func hideSmoothly() {
        animationGeneration &+= 1
        let gen = animationGeneration
        guard isVisible else {
            model.image = nil
            model.text = nil
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.animationGeneration == gen else { return }
                self.orderOut(nil)
                self.alphaValue = 1.0
                self.model.image = nil
                self.model.text = nil
            }
        })
    }

    private struct PreviewContentView: View {
        @ObservedObject var model: Model
        let padding: CGFloat
        let footerHeight: CGFloat

        var body: some View {
            VStack(spacing: 0) {
                if let img = model.image {
                    ZStack {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, padding)
                    .padding(.horizontal, padding)
                } else if let text = model.text {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(text)
                            .font(.system(size: 12.5))
                            .lineSpacing(3.5)
                            .foregroundStyle(.white.opacity(0.94))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .padding(.top, padding)
                    .padding(.horizontal, padding)
                }

                HStack(spacing: 6) {
                    Image(systemName: model.image != nil ? "photo" : "doc.text")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(model.caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(height: footerHeight)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: NSColor(white: 0.10, alpha: 0.94)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.9)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

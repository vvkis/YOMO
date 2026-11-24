import Foundation
import AppKit
import SwiftUI
import CoreKit

// MARK: - Domain Models

public enum CleanerSafetyLevel: Int, Comparable, Sendable, CaseIterable {
    case safe = 0        // Pure regenerable caches / logs / build artifacts
    case recommended = 1 // Browser / Electron / package caches (respects running apps)
    case review = 2      // User-facing items (Trash, Installers, Large Downloads, Archives, Chat Caches)

    public static func < (lhs: CleanerSafetyLevel, rhs: CleanerSafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var badgeTitle: String {
        switch self {
        case .safe: return "极安全"
        case .recommended: return "推荐清理"
        case .review: return "请先确认"
        }
    }

    public var defaultSelected: Bool {
        switch self {
        case .safe, .recommended: return true
        case .review: return false
        }
    }
}

public enum CleanerDeletionAction: String, Sendable {
    /// Deletes children inside a cache directory while preserving the directory itself
    case deleteContents
    /// Moves a user file/folder to macOS Trash (reversible with Put Back)
    case moveToTrash
    /// Permanently removes an item already inside ~/.Trash
    case emptyTrashItem

    public var actionLabel: String {
        switch self {
        case .deleteContents: return "清除缓存"
        case .moveToTrash: return "移至废纸篓"
        case .emptyTrashItem: return "清空废纸篓"
        }
    }

    public var completedLabel: String {
        switch self {
        case .deleteContents: return "已清除"
        case .moveToTrash: return "已移至废纸篓"
        case .emptyTrashItem: return "已清空"
        }
    }
}

public enum CleanerCategoryID: String, CaseIterable, Identifiable, Sendable {
    case systemAndLogs
    case browsersAndApps
    case developerCaches
    case appLeftovers
    case installers
    case trash
    case largeDownloads

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .systemAndLogs: return "系统与应用缓存日志"
        case .browsersAndApps: return "浏览器与桌面软件缓存"
        case .developerCaches: return "开发者工具与包管理缓存"
        case .appLeftovers: return "已卸载软件残留"
        case .installers: return "旧安装包与磁盘镜像"
        case .trash: return "废纸篓"
        case .largeDownloads: return "下载目录大文件 (≥100MB)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .systemAndLogs: return "应用缓存与日志"
        case .browsersAndApps: return "浏览器与软件"
        case .developerCaches: return "开发者缓存"
        case .appLeftovers: return "卸载残留"
        case .installers: return "旧安装包"
        case .trash: return "废纸篓"
        case .largeDownloads: return "大文件"
        }
    }

    public var subtitle: String {
        switch self {
        case .systemAndLogs: return "自动跳过 Apple 核心服务与 iCloud，仅清理可重建的用户缓存与崩溃日志"
        case .browsersAndApps: return "仅清理网页/GPU/代码缓存，不触碰书签、Cookie、密码与聊天记录"
        case .developerCaches: return "清理 macOS「系统数据」膨胀大户：Xcode、Homebrew、npm、pip、Cargo 等"
        case .appLeftovers: return "保守比对本机全部已安装应用与 LaunchServices，检出孤儿残留并移至废纸篓"
        case .installers: return "下载与桌面中的 .dmg / .pkg / .xip 安装包，清理时安全移至废纸篓"
        case .trash: return "永久清空 ~/.Trash 中已删除的文件以立即回收 APFS 空间"
        case .largeDownloads: return "列出 ~/Downloads 中 ≥100 MB 的单文件供手动勾选，清理时移至废纸篓"
        }
    }

    public var symbolName: String {
        switch self {
        case .systemAndLogs: return "doc.text.magnifyingglass"
        case .browsersAndApps: return "globe"
        case .developerCaches: return "hammer.fill"
        case .appLeftovers: return "app.dashed"
        case .installers: return "shippingbox.fill"
        case .trash: return "trash.fill"
        case .largeDownloads: return "externaldrive.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .systemAndLogs: return .teal
        case .browsersAndApps: return .blue
        case .developerCaches: return .indigo
        case .appLeftovers: return .pink
        case .installers: return .orange
        case .trash: return .red
        case .largeDownloads: return .purple
        }
    }
}

// MARK: - Startup / Login Items Models

public enum SpaceCleanerConsoleTab: String, CaseIterable, Identifiable {
    case cleanup = "空间清理"
    case startup = "开机启动项"

    public var id: String { rawValue }
}

public enum StartupItemScope: String, CaseIterable, Identifiable, Sendable {
    case userLaunchAgent
    case globalLaunchAgent
    case globalLaunchDaemon
    case appLoginItem

    public var id: String { rawValue }

    public var badgeTitle: String {
        switch self {
        case .userLaunchAgent: return "用户代理"
        case .globalLaunchAgent: return "系统代理"
        case .globalLaunchDaemon: return "系统守护"
        case .appLoginItem: return "应用登录项"
        }
    }

    public var tintColor: Color {
        switch self {
        case .userLaunchAgent: return .blue
        case .globalLaunchAgent: return .indigo
        case .globalLaunchDaemon: return .purple
        case .appLoginItem: return .teal
        }
    }
}

public enum StartupItemFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case user = "用户代理"
    case system = "系统级"
    case loginItems = "应用内嵌"
    case orphaned = "已失效残留"

    public var id: String { rawValue }
}

public struct StartupItemInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let displayName: String
    public let scope: StartupItemScope
    public let sourcePath: String
    public let executablePath: String?
    public let appBundlePath: String?
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let isEnabled: Bool
    public let isStoredInDisabledVault: Bool
    public let isRunning: Bool
    public let isOrphanedBinary: Bool
    public let canToggleDirectly: Bool
    public let canMoveToTrash: Bool

    public var displaySourcePath: String {
        let home = NSHomeDirectory()
        if sourcePath.hasPrefix(home) {
            return "~" + sourcePath.dropFirst(home.count)
        }
        return sourcePath
    }
}

public struct CleanerItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let category: CleanerCategoryID
    public let title: String
    public let detail: String
    public let paths: [String]
    public let byteSize: UInt64
    public let fileCount: Int
    public let safety: CleanerSafetyLevel
    public let deletionAction: CleanerDeletionAction
    public let runningAppName: String?
    public let modifiedAt: Date?
    public var isSelected: Bool

    public init(
        id: String,
        category: CleanerCategoryID,
        title: String,
        detail: String,
        paths: [String],
        byteSize: UInt64,
        fileCount: Int,
        safety: CleanerSafetyLevel,
        deletionAction: CleanerDeletionAction,
        runningAppName: String? = nil,
        modifiedAt: Date? = nil,
        isSelected: Bool
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.paths = paths
        self.byteSize = byteSize
        self.fileCount = fileCount
        self.safety = safety
        self.deletionAction = deletionAction
        self.runningAppName = runningAppName
        self.modifiedAt = modifiedAt
        self.isSelected = isSelected
    }

    public var primaryPath: String? {
        paths.first
    }

    public var displayPath: String {
        guard let first = paths.first else { return "" }
        let home = NSHomeDirectory()
        if first.hasPrefix(home) {
            return "~" + first.dropFirst(home.count)
        }
        return first
    }
}

public struct CleanerCategorySection: Identifiable, Sendable {
    public let id: CleanerCategoryID
    public var items: [CleanerItem]
    public let permissionNotice: String?

    public init(id: CleanerCategoryID, items: [CleanerItem], permissionNotice: String? = nil) {
        self.id = id
        self.items = items
        self.permissionNotice = permissionNotice
    }

    public var totalBytes: UInt64 {
        items.reduce(0) { $0 &+ $1.byteSize }
    }

    public var selectedBytes: UInt64 {
        items.reduce(0) { $0 &+ ($1.isSelected ? $1.byteSize : 0) }
    }

    public var selectedCount: Int {
        items.filter(\.isSelected).count
    }

    public var isAllSelected: Bool {
        !items.isEmpty && selectedCount == items.count
    }

    public var isPartiallySelected: Bool {
        selectedCount > 0 && selectedCount < items.count
    }
}

public struct CleanupItemRecord: Identifiable, Sendable {
    public let id: String
    public let category: CleanerCategoryID
    public let title: String
    public let freedBytes: UInt64
    public let removedFileCount: Int
    public let action: CleanerDeletionAction
    public let skippedReason: String?

    public var succeeded: Bool {
        skippedReason == nil || freedBytes > 0
    }
}

public struct CleanupCategorySummary: Identifiable, Sendable {
    public let id: CleanerCategoryID
    public let freedBytes: UInt64
    public let cleanedItems: [CleanupItemRecord]
    public let skippedItems: [CleanupItemRecord]
}

public struct CleanupReport: Identifiable, Sendable {
    public let id = UUID()
    public let finishedAt: Date
    public let durationSeconds: TimeInterval
    public let totalFreedBytes: UInt64
    public let totalRemovedFiles: Int
    public let categorySummaries: [CleanupCategorySummary]
    public let hadPermissionRestrictions: Bool

    public var totalCleanedEntries: Int {
        categorySummaries.reduce(0) { $0 + $1.cleanedItems.count }
    }

    public var totalSkippedEntries: Int {
        categorySummaries.reduce(0) { $0 + $1.skippedItems.count }
    }
}

public struct DiskVolumeSummary: Sendable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let usedBytes: UInt64
    public let usageFraction: Double

    public static let empty = DiskVolumeSummary(totalBytes: 0, availableBytes: 0, usedBytes: 0, usageFraction: 0)

    public static func sampleBootVolume() -> DiskVolumeSummary {
        let rootURL = URL(fileURLWithPath: "/")
        guard let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]),
        let total = values.volumeTotalCapacity, total > 0 else {
            return .empty
        }
        let availInt64 = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        let totalU = UInt64(max(0, total))
        let availU = UInt64(max(0, availInt64))
        let usedU = totalU > availU ? (totalU - availU) : 0
        let frac = totalU > 0 ? min(1.0, max(0.0, Double(usedU) / Double(totalU))) : 0
        return DiskVolumeSummary(
            totalBytes: totalU,
            availableBytes: availU,
            usedBytes: usedU,
            usageFraction: frac
        )
    }
}

public enum SpaceByteFormatter {
    public static func format(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 B" }
        let b = Double(bytes)
        let kb = 1_000.0
        let mb = 1_000_000.0
        let gb = 1_000_000_000.0
        if b >= gb {
            return String(format: "%.2f GB", b / gb)
        }
        if b >= mb {
            let v = b / mb
            return v >= 100 ? String(format: "%.0f MB", v) : String(format: "%.1f MB", v)
        }
        if b >= kb {
            return String(format: "%.0f KB", b / kb)
        }
        return "\(bytes) B"
    }
}

// MARK: - Store

@MainActor
public final class SpaceCleanerStore: ObservableObject {
    @Published public private(set) var volumeSummary: DiskVolumeSummary = .sampleBootVolume()
    @Published public private(set) var sections: [CleanerCategorySection] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var scanProgressText: String = ""
    @Published public private(set) var isCleaning: Bool = false
    @Published public private(set) var cleanProgressText: String = ""
    @Published public private(set) var lastScanDate: Date? = nil
    @Published public private(set) var lastReport: CleanupReport? = nil
    @Published public var expandedCategories: Set<CleanerCategoryID> = [.systemAndLogs, .browsersAndApps, .developerCaches]

    // Startup / Login Items Inspector state (on-demand, zero background polling)
    @Published public var consoleTab: SpaceCleanerConsoleTab = .cleanup
    @Published public var startupFilter: StartupItemFilter = .all
    @Published public private(set) var startupItems: [StartupItemInfo] = []
    @Published public private(set) var isScanningStartupItems: Bool = false
    @Published public private(set) var hasScannedStartupItems: Bool = false
    @Published public var startupStatusMessage: String? = nil
    @Published public private(set) var togglingStartupItemID: String? = nil

    private var scanGeneration: UInt64 = 0
    private let workQueue = DispatchQueue(label: "com.yomo.spacecleaner.worker", qos: .userInitiated)
    private let startupIconCache = NSCache<NSString, NSImage>()

    public init() {}

    // MARK: - Computed Summaries

    public var hasScanned: Bool {
        lastScanDate != nil
    }

    public var totalReclaimableBytes: UInt64 {
        sections.reduce(0) { $0 &+ $1.totalBytes }
    }

    public var selectedBytes: UInt64 {
        sections.reduce(0) { $0 &+ $1.selectedBytes }
    }

    public var selectedItemCount: Int {
        sections.reduce(0) { $0 + $1.selectedCount }
    }

    public var totalItemCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    public var overviewSubtitle: String {
        if isScanning {
            return "正在扫描…"
        }
        if isCleaning {
            return "正在清理…"
        }
        if let report = lastReport, totalReclaimableBytes == 0 {
            return "已释放 \(SpaceByteFormatter.format(report.totalFreedBytes))"
        }
        if hasScanned {
            return totalReclaimableBytes > 0
                ? "可释放 \(SpaceByteFormatter.format(totalReclaimableBytes))"
                : "空间非常干净"
        }
        if volumeSummary.availableBytes > 0 {
            return "可用 \(SpaceByteFormatter.format(volumeSummary.availableBytes))"
        }
        return "一键扫描释放空间"
    }

    // MARK: - Scanning (On-Demand, Zero Subprocesses, Zero Idle Overhead)

    public func refreshVolumeSummary() {
        volumeSummary = DiskVolumeSummary.sampleBootVolume()
    }

    public func startScan(clearReport: Bool = true) {
        guard !isScanning && !isCleaning else { return }
        scanGeneration &+= 1
        let gen = scanGeneration
        isScanning = true
        scanProgressText = "正在分析用户缓存、开发工具与大文件…"
        if clearReport {
            lastReport = nil
        }

        // Snapshot running apps on MainActor so the scanner can protect active browsers/IDEs
        let runningApps = Self.snapshotRunningApps()

        workQueue.async { [weak self] in
            let vol = DiskVolumeSummary.sampleBootVolume()
            let scannedSections = SpaceCleanerEngine.scanAll(runningApps: runningApps) { [weak self] statusText in
                Task { @MainActor [weak self] in
                    guard let self, self.scanGeneration == gen, self.isScanning else { return }
                    self.scanProgressText = statusText
                }
            }

            Task { @MainActor [weak self] in
                guard let self, self.scanGeneration == gen else { return }
                self.volumeSummary = vol
                self.sections = scannedSections
                self.isScanning = false
                self.scanProgressText = ""
                self.lastScanDate = Date()

                // Auto-expand top non-empty categories with biggest savings
                let nonEmpty = scannedSections.filter { !$0.items.isEmpty }
                if !nonEmpty.isEmpty {
                    let topIDs = nonEmpty.sorted { $0.totalBytes > $1.totalBytes }.prefix(3).map(\.id)
                    self.expandedCategories = Set(topIDs)
                }
            }
        }
    }

    public func cancelScan() {
        guard isScanning else { return }
        scanGeneration &+= 1
        isScanning = false
        scanProgressText = ""
    }

    // MARK: - Selection Controls

    public func toggleCategoryExpanded(_ id: CleanerCategoryID) {
        if expandedCategories.contains(id) {
            expandedCategories.remove(id)
        } else {
            expandedCategories.insert(id)
        }
    }

    public func toggleCategorySelection(_ id: CleanerCategoryID) {
        guard let idx = sections.firstIndex(where: { $0.id == id }) else { return }
        let targetSelected = !sections[idx].isAllSelected
        for i in sections[idx].items.indices {
            sections[idx].items[i].isSelected = targetSelected
        }
    }

    public func toggleItemSelection(category: CleanerCategoryID, itemID: String) {
        guard let sIdx = sections.firstIndex(where: { $0.id == category }),
              let iIdx = sections[sIdx].items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        sections[sIdx].items[iIdx].isSelected.toggle()
    }

    public func applySmartSelection() {
        for sIdx in sections.indices {
            for iIdx in sections[sIdx].items.indices {
                let item = sections[sIdx].items[iIdx]
                sections[sIdx].items[iIdx].isSelected = item.safety.defaultSelected && (item.runningAppName == nil)
            }
        }
    }

    public func selectAllItems() {
        for sIdx in sections.indices {
            for iIdx in sections[sIdx].items.indices {
                sections[sIdx].items[iIdx].isSelected = true
            }
        }
    }

    public func clearAllSelections() {
        for sIdx in sections.indices {
            for iIdx in sections[sIdx].items.indices {
                sections[sIdx].items[iIdx].isSelected = false
            }
        }
    }

    public func dismissReport() {
        lastReport = nil
    }

    // MARK: - Executing Cleanup

    public func cleanSelectedItems() {
        guard !isCleaning && !isScanning else { return }
        let selectedItems = sections.flatMap { $0.items.filter(\.isSelected) }
        guard !selectedItems.isEmpty else { return }

        isCleaning = true
        cleanProgressText = "正在安全清理 \(selectedItems.count) 项…"
        lastReport = nil

        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() }
        )

        workQueue.async { [weak self] in
            let report = SpaceCleanerEngine.executeCleanup(
                items: selectedItems,
                runningBundleIDs: runningBundleIDs
            ) { [weak self] statusText in
                Task { @MainActor [weak self] in
                    self?.cleanProgressText = statusText
                }
            }
            let updatedVol = DiskVolumeSummary.sampleBootVolume()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.volumeSummary = updatedVol
                self.lastReport = report
                self.isCleaning = false
                self.cleanProgressText = ""

                // Remove fully cleaned items from current sections so remaining unchecked items stay visible
                let cleanedIDs = Set(
                    report.categorySummaries
                        .flatMap(\.cleanedItems)
                        .filter { $0.skippedReason == nil }
                        .map(\.id)
                )
                for sIdx in self.sections.indices {
                    self.sections[sIdx].items.removeAll { cleanedIDs.contains($0.id) }
                }
            }
        }
    }

    // MARK: - Startup Items Inspector (Zero Subprocess, On-Demand)

    public var filteredStartupItems: [StartupItemInfo] {
        switch startupFilter {
        case .all:
            return startupItems
        case .user:
            return startupItems.filter { $0.scope == .userLaunchAgent }
        case .system:
            return startupItems.filter { $0.scope == .globalLaunchAgent || $0.scope == .globalLaunchDaemon }
        case .loginItems:
            return startupItems.filter { $0.scope == .appLoginItem }
        case .orphaned:
            return startupItems.filter(\.isOrphanedBinary)
        }
    }

    public var enabledStartupCount: Int {
        startupItems.filter(\.isEnabled).count
    }

    public var runningStartupCount: Int {
        startupItems.filter(\.isRunning).count
    }

    public var orphanedStartupCount: Int {
        startupItems.filter(\.isOrphanedBinary).count
    }

    public func appIcon(for item: StartupItemInfo) -> NSImage? {
        guard let appPath = item.appBundlePath, !appPath.isEmpty else { return nil }
        let key = appPath as NSString
        if let cached = startupIconCache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        startupIconCache.setObject(icon, forKey: key)
        return icon
    }

    public func refreshStartupItems() {
        guard !isScanningStartupItems else { return }
        isScanningStartupItems = true
        let runningSnap = Self.snapshotRunningProcesses()

        workQueue.async { [weak self] in
            let items = SpaceCleanerEngine.scanStartupItems(runningSnap: runningSnap)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startupItems = items
                self.isScanningStartupItems = false
                self.hasScannedStartupItems = true
            }
        }
    }

    /// Directly toggles a user-level LaunchAgent (~/Library/LaunchAgents) ON or OFF without root privileges.
    /// Uses a reversible disabled vault + explicit launchctl enable/disable & bootstrap/bootout so changes take effect immediately and survive reboot.
    public func setUserStartupItemEnabled(_ item: StartupItemInfo, enabled: Bool) {
        guard item.canToggleDirectly, item.scope == .userLaunchAgent, togglingStartupItemID == nil else {
            return
        }
        togglingStartupItemID = item.id
        let itemCopy = item
        let runningSnap = Self.snapshotRunningProcesses()

        workQueue.async { [weak self] in
            let outcome = SpaceCleanerEngine.toggleUserLaunchAgent(itemCopy, enabled: enabled)
            let updatedItems = SpaceCleanerEngine.scanStartupItems(runningSnap: runningSnap)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.togglingStartupItemID = nil
                self.startupItems = updatedItems
                self.startupStatusMessage = outcome.message
            }
        }
    }

    /// Safely moves a user-owned LaunchAgent plist (active or disabled vault) to macOS Trash (reversible via Put Back).
    public func trashUserStartupItem(_ item: StartupItemInfo) {
        guard item.canMoveToTrash, item.scope == .userLaunchAgent else { return }
        let home = NSHomeDirectory()
        let activeDir = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents").standardizedFileURL.path
        let vaultDir = SpaceCleanerEngine.disabledVaultURL(home: home).standardizedFileURL.path
        let targetURL = URL(fileURLWithPath: item.sourcePath).standardizedFileURL
        let inAllowedDir = targetURL.path.hasPrefix(activeDir + "/") || targetURL.path.hasPrefix(vaultDir + "/")
        guard inAllowedDir, targetURL.pathExtension.lowercased() == "plist" else {
            return
        }
        do {
            try FileManager.default.trashItem(at: targetURL, resultingItemURL: nil)
            startupItems.removeAll { $0.id == item.id }
            startupStatusMessage = "已将「\(item.displayName)」的启动配置移至废纸篓（可在废纸篓中放回原处）"
        } catch {
            startupStatusMessage = "移除「\(item.displayName)」失败：\(error.localizedDescription)"
        }
    }

    public func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Finder & Permissions Helpers

    public func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openTrashInFinder() {
        let trashURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        NSWorkspace.shared.open(trashURL)
    }

    private static func snapshotRunningApps() -> [String: String] {
        var map: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            let display = app.localizedName ?? app.bundleIdentifier ?? ""
            if let bid = app.bundleIdentifier?.lowercased() {
                map[bid] = display
            }
            if let name = app.localizedName?.lowercased(), !name.isEmpty {
                map["name:\(name)"] = display
            }
        }
        return map
    }

    private static func snapshotRunningProcesses() -> (bundleIDs: Set<String>, executablePaths: Set<String>, executableNames: Set<String>) {
        var bids = Set<String>()
        var paths = Set<String>()
        var names = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier?.lowercased() {
                bids.insert(bid)
            }
            if let execURL = app.executableURL {
                paths.insert(execURL.standardizedFileURL.path.lowercased())
                names.insert(execURL.lastPathComponent.lowercased())
            }
            if let loc = app.localizedName?.lowercased() {
                names.insert(loc)
            }
        }
        return (bids, paths, names)
    }
}

// MARK: - Native Zero-Subprocess Rule Engine & Safety Sandbox

private enum SpaceCleanerEngine {
    /// Minimum item threshold (512 KB) to avoid noisy 4 KB empty cache folders
    private static let minDisplayBytes: UInt64 = 512 * 1024
    /// Threshold for Large Downloads review list (100 MB)
    private static let largeFileThresholdBytes: UInt64 = 100 * 1024 * 1024

    /// Hard-coded protected paths / bundle prefixes that must NEVER be cleaned or offered for deletion
    private static let protectedCacheEntryPrefixes: [String] = [
        "com.apple.",
        "apple.",
        "group.com.apple.",
        "cloudkit",
        "familycircle",
        "knowledge",
        "geoservices",
        "passkit",
        "com.yomo.",
        "yomo"
    ]

    private static let protectedCacheExactNames: Set<String> = [
        "com.spotify.client",    // Offline downloaded Spotify music resides under Caches on macOS
        "com.netease.163music",  // NetEase Cloud Music may store offline audio/cache data
        "com.tencent.QQMusicMac",
        "com.google.Keystone",   // Google auto-updater lock
        "FamilyCircle",
        "CloudKit",
        "PassKit",
        "GeoServices",
        "SiriTTS",
        "VoiceTrigger",
        "CrashReporter",
        "Metadata",
        "Spotlight",
        "com.apple.bird",
        "com.apple.nsurlsessiond",
        "com.apple.Safari"
    ]

    /// Protected reverse-DNS prefixes that must NEVER be flagged as uninstalled app leftovers
    private static let protectedLeftoverPrefixes: [String] = [
        "com.apple.",
        "group.com.apple.",
        "com.yomo.",
        "org.swift.",
        "com.google.keystone",
        "com.microsoft.autoupdate",
        "com.adobe.acc",
        "com.adobe.armdc",
        "com.oracle.java"
    ]

    private static let forbiddenAbsoluteFragments: [String] = [
        "/.ssh",
        "/.gnupg",
        "/.aws",
        "/.kube",
        "/Keychains",
        "/Passwords",
        "/Mobile Documents",
        "/CloudDocs",
        "/Application Support/YOMO"
    ]

    private struct StaticRule {
        let id: String
        let category: CleanerCategoryID
        let title: String
        let detail: String
        let relativePaths: [String]
        let safety: CleanerSafetyLevel
        let action: CleanerDeletionAction
        let relatedBundleIDs: [String]
    }

    /// Curated macOS cleanup rules modeled on CleanMyMac / Pearcleaner / Mole / DevCleaner best practices.
    /// Every path is strictly relative to `~` (user home directory).
    private static let staticRules: [StaticRule] = [
        // --- 1. System & User Logs ---
        StaticRule(
            id: "sys.diagnosticReports",
            category: .systemAndLogs,
            title: "应用崩溃与诊断报告",
            detail: "系统生成的 .ips / .crash 崩溃日志，删除完全不影响系统与软件运行",
            relativePaths: ["Library/Logs/DiagnosticReports", "Library/Application Support/CrashReporter"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "sys.userLogs",
            category: .systemAndLogs,
            title: "用户软件运行日志",
            detail: "各类 macOS 应用写入 ~/Library/Logs 的历史调试日志文件",
            relativePaths: ["Library/Logs"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "sys.savedAppState",
            category: .systemAndLogs,
            title: "历史窗口恢复快照",
            detail: "应用关闭后遗留的窗口状态缓存（Saved Application State）",
            relativePaths: ["Library/Saved Application State"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),

        // --- 2. Browsers & Desktop Apps (Strictly cache subdirs — NEVER touch Cookies/Bookmarks/Logins/Chats) ---
        StaticRule(
            id: "app.chromeCache",
            category: .browsersAndApps,
            title: "Google Chrome 网页与媒体缓存",
            detail: "仅清理 Chrome 缓存目录，保留书签、历史记录、Cookie 与已保存密码",
            relativePaths: [
                "Library/Caches/Google/Chrome",
                "Library/Application Support/Google/Chrome/Default/Code Cache",
                "Library/Application Support/Google/Chrome/Default/GPUCache",
                "Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.google.chrome"]
        ),
        StaticRule(
            id: "app.arcCache",
            category: .browsersAndApps,
            title: "Arc 浏览器缓存",
            detail: "仅清理 Arc 网页与 GPU 缓存，保留空间标签、书签与登录态",
            relativePaths: [
                "Library/Caches/company.thebrowser.Browser",
                "Library/Application Support/Arc/User Data/Default/Code Cache",
                "Library/Application Support/Arc/User Data/Default/GPUCache"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["company.thebrowser.browser"]
        ),
        StaticRule(
            id: "app.edgeCache",
            category: .browsersAndApps,
            title: "Microsoft Edge 浏览器缓存",
            detail: "仅清理 Edge 网页、代码与 GPU 缓存，保留个人数据",
            relativePaths: [
                "Library/Caches/Microsoft Edge",
                "Library/Application Support/Microsoft Edge/Default/Code Cache",
                "Library/Application Support/Microsoft Edge/Default/GPUCache"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.microsoft.edgemac"]
        ),
        StaticRule(
            id: "app.braveCache",
            category: .browsersAndApps,
            title: "Brave 浏览器缓存",
            detail: "仅清理 Brave 网页与 GPU 缓存，保留书签与钱包配置",
            relativePaths: [
                "Library/Caches/BraveSoftware/Brave-Browser",
                "Library/Application Support/BraveSoftware/Brave-Browser/Default/Code Cache",
                "Library/Application Support/BraveSoftware/Brave-Browser/Default/GPUCache"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.brave.browser"]
        ),
        StaticRule(
            id: "app.firefoxCache",
            category: .browsersAndApps,
            title: "Firefox 浏览器缓存",
            detail: "仅清理 Firefox 磁盘缓存（~/Library/Caches/Firefox），保留书签与配置",
            relativePaths: ["Library/Caches/Firefox"],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["org.mozilla.firefox"]
        ),
        StaticRule(
            id: "app.vscodeCache",
            category: .browsersAndApps,
            title: "VS Code 编辑器缓存",
            detail: "清理 Electron GPU/V8 代码缓存与旧扩展安装包缓存，不影响设置与插件",
            relativePaths: [
                "Library/Application Support/Code/Cache",
                "Library/Application Support/Code/CachedData",
                "Library/Application Support/Code/Code Cache",
                "Library/Application Support/Code/GPUCache",
                "Library/Application Support/Code/CachedExtensionVSIXs"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.microsoft.vscode"]
        ),
        StaticRule(
            id: "app.cursorCache",
            category: .browsersAndApps,
            title: "Cursor 编辑器缓存",
            detail: "清理 Cursor 渲染与旧版本扩展缓存，不影响工作区配置与登录",
            relativePaths: [
                "Library/Application Support/Cursor/Cache",
                "Library/Application Support/Cursor/CachedData",
                "Library/Application Support/Cursor/Code Cache",
                "Library/Application Support/Cursor/GPUCache",
                "Library/Application Support/Cursor/CachedExtensionVSIXs"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.todesktop.230313mzl4w4u92"]
        ),
        StaticRule(
            id: "app.slackCache",
            category: .browsersAndApps,
            title: "Slack 桌面端缓存",
            detail: "清理 Slack 图片与网页渲染缓存，不删除账号与消息",
            relativePaths: [
                "Library/Application Support/Slack/Cache",
                "Library/Application Support/Slack/Code Cache",
                "Library/Application Support/Slack/GPUCache",
                "Library/Application Support/Slack/Service Worker/CacheStorage"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.tinyspeck.slackmacgap"]
        ),
        StaticRule(
            id: "app.discordCache",
            category: .browsersAndApps,
            title: "Discord 桌面端缓存",
            detail: "清理 Discord 频道图片与媒体临时缓存",
            relativePaths: [
                "Library/Application Support/discord/Cache",
                "Library/Application Support/discord/Code Cache",
                "Library/Application Support/discord/GPUCache"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.hnc.discord"]
        ),
        StaticRule(
            id: "app.notionCache",
            category: .browsersAndApps,
            title: "Notion 桌面端缓存",
            detail: "清理 Notion 页面渲染与媒体缓存，云端笔记不受影响",
            relativePaths: [
                "Library/Application Support/Notion/Cache",
                "Library/Application Support/Notion/Code Cache",
                "Library/Application Support/Notion/GPUCache"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["notion.id"]
        ),
        StaticRule(
            id: "app.figmaCache",
            category: .browsersAndApps,
            title: "Figma 桌面端缓存",
            detail: "清理 Figma 画布 GPU 与静态资源缓存，云端设计稿安全无损",
            relativePaths: [
                "Library/Application Support/Figma/Cache",
                "Library/Application Support/Figma/Code Cache",
                "Library/Application Support/Figma/GPUCache"
            ],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.figma.desktop"]
        ),
        StaticRule(
            id: "app.larkCache",
            category: .browsersAndApps,
            title: "飞书 / Lark 临时缓存",
            detail: "清理飞书渲染与临时缓存，不触碰本地消息数据库",
            relativePaths: [
                "Library/Caches/com.electron.lark",
                "Library/Caches/com.bytedance.lark",
                "Library/Application Support/LarkShell/Cache",
                "Library/Application Support/LarkShell/GPUCache"
            ],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: ["com.electron.lark", "com.bytedance.lark"]
        ),
        StaticRule(
            id: "app.wechatCache",
            category: .browsersAndApps,
            title: "微信沙盒临时缓存",
            detail: "仅清理微信容器内 Library/Caches 临时缓存，绝不删除聊天记录与文件",
            relativePaths: [
                "Library/Containers/com.tencent.xinWeChat/Data/Library/Caches"
            ],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: ["com.tencent.xinwechat"]
        ),
        StaticRule(
            id: "app.qqCache",
            category: .browsersAndApps,
            title: "QQ 沙盒临时缓存",
            detail: "仅清理 QQ 容器内 Library/Caches 临时缓存，不删除聊天记录",
            relativePaths: [
                "Library/Containers/com.tencent.qq/Data/Library/Caches"
            ],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: ["com.tencent.qq"]
        ),

        // --- 3. Developer Tools & Package Manager Caches ---
        StaticRule(
            id: "dev.xcodeDerivedData",
            category: .developerCaches,
            title: "Xcode DerivedData 编译产物",
            detail: "Xcode 中间编译索引与构建产物，清理后下次构建自动重建，常可释放数 GB",
            relativePaths: ["Library/Developer/Xcode/DerivedData"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: ["com.apple.dt.xcode"]
        ),
        StaticRule(
            id: "dev.xcodeCoreSimCaches",
            category: .developerCaches,
            title: "Xcode 模拟器缓存 (CoreSimulator)",
            detail: "iOS/macOS 模拟器的 dyld 共享缓存与临时构建数据",
            relativePaths: ["Library/Developer/CoreSimulator/Caches"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: ["com.apple.iphonesimulator"]
        ),
        StaticRule(
            id: "dev.xcodeDeviceSupport",
            category: .developerCaches,
            title: "Xcode 真机调试符号 (DeviceSupport)",
            detail: "历史 iOS / watchOS 真机系统符号包，重新连接真机时会按需重新提取",
            relativePaths: [
                "Library/Developer/Xcode/iOS DeviceSupport",
                "Library/Developer/Xcode/watchOS DeviceSupport",
                "Library/Developer/Xcode/tvOS DeviceSupport"
            ],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: ["com.apple.dt.xcode"]
        ),
        StaticRule(
            id: "dev.xcodeArchives",
            category: .developerCaches,
            title: "Xcode 历史归档包 (Archives)",
            detail: "过往打包上架/导出的 .xcarchive 归档，若需保留历史 dSYM 请勿勾选",
            relativePaths: ["Library/Developer/Xcode/Archives"],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: ["com.apple.dt.xcode"]
        ),
        StaticRule(
            id: "dev.swiftPM",
            category: .developerCaches,
            title: "Swift Package Manager 缓存",
            detail: "SwiftPM 源码仓库镜像与校验缓存，构建时自动按需拉取",
            relativePaths: ["Library/Caches/org.swift.swiftpm", "Library/org.swift.swiftpm/caches"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.cocoapods",
            category: .developerCaches,
            title: "CocoaPods 下载缓存",
            detail: "CocoaPods 历史下载的 Pod 源码压缩包缓存",
            relativePaths: ["Library/Caches/CocoaPods"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.homebrew",
            category: .developerCaches,
            title: "Homebrew 下载缓存",
            detail: "brew 安装/升级软件后遗留的旧版本 bottle 与 cask 压缩包",
            relativePaths: ["Library/Caches/Homebrew"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.npm",
            category: .developerCaches,
            title: "npm 包下载缓存",
            detail: "Node.js npm 本地下载缓存（~/.npm/_cacache），不影响已安装的 node_modules",
            relativePaths: [".npm/_cacache", ".npm/_logs"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.yarn",
            category: .developerCaches,
            title: "Yarn 包缓存",
            detail: "Yarn 离线包压缩缓存（~/Library/Caches/Yarn）",
            relativePaths: ["Library/Caches/Yarn"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.pnpmCache",
            category: .developerCaches,
            title: "pnpm 元数据与临时缓存",
            detail: "pnpm 缓存目录（不删硬链接 Store，避免影响已有项目）",
            relativePaths: ["Library/Caches/pnpm"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.bun",
            category: .developerCaches,
            title: "Bun 包安装缓存",
            detail: "Bun 全局安装缓存（~/.bun/install/cache）",
            relativePaths: [".bun/install/cache"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.pip",
            category: .developerCaches,
            title: "Python pip 下载缓存",
            detail: "pip 安装 Python 库时缓存的 .whl 与源码 tar.gz",
            relativePaths: ["Library/Caches/pip"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.uv",
            category: .developerCaches,
            title: "Python uv 缓存",
            detail: "uv 工具下载的 wheel 与构建缓存",
            relativePaths: ["Library/Caches/uv", ".cache/uv"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.poetry",
            category: .developerCaches,
            title: "Python Poetry 缓存",
            detail: "Poetry 包管理器下载缓存（不删除已建虚拟环境）",
            relativePaths: ["Library/Caches/pypoetry/cache", "Library/Caches/pypoetry/artifacts"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.condaPkgs",
            category: .developerCaches,
            title: "Conda / Miniconda 离线包缓存",
            detail: "Conda pkgs 目录下下载的压缩包缓存（若多环境共享硬链接请先确认）",
            relativePaths: [".conda/pkgs", "miniconda3/pkgs", "anaconda3/pkgs", "opt/miniconda3/pkgs", "opt/anaconda3/pkgs"],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.cargo",
            category: .developerCaches,
            title: "Rust Cargo Crate 缓存",
            detail: "Cargo 下载的 .crate 压缩包缓存，下次编译按需重新拉取",
            relativePaths: [".cargo/registry/cache"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.goBuild",
            category: .developerCaches,
            title: "Go 编译缓存 (go-build)",
            detail: "Go 编译器生成的中间对象缓存（~/Library/Caches/go-build）",
            relativePaths: ["Library/Caches/go-build"],
            safety: .safe,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.gradle",
            category: .developerCaches,
            title: "Gradle 构建与依赖缓存",
            detail: "~/.gradle/caches 下的历史构建与依赖缓存，下次构建将重新拉取",
            relativePaths: [".gradle/caches"],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.maven",
            category: .developerCaches,
            title: "Maven 本地仓库缓存 (.m2)",
            detail: "~/.m2/repository 中的 Java 依赖 jar 包缓存，清理后需联网重新下载",
            relativePaths: [".m2/repository"],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: []
        ),
        StaticRule(
            id: "dev.jetbrains",
            category: .developerCaches,
            title: "JetBrains IDE 索引缓存",
            detail: "IntelliJ / WebStorm / PyCharm / GoLand 历史缓存，打开项目会自动重建索引",
            relativePaths: ["Library/Caches/JetBrains"],
            safety: .recommended,
            action: .deleteContents,
            relatedBundleIDs: ["com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.webstorm", "com.jetbrains.goland"]
        ),
        StaticRule(
            id: "dev.huggingface",
            category: .developerCaches,
            title: "Hugging Face 本地模型缓存",
            detail: "~/.cache/huggingface 中下载的大模型权重缓存，体积大但重新下载耗时",
            relativePaths: [".cache/huggingface"],
            safety: .review,
            action: .deleteContents,
            relatedBundleIDs: []
        )
    ]

    // MARK: - Full Scan

    static func scanAll(
        runningApps: [String: String],
        onProgress: @escaping @Sendable (String) -> Void
    ) -> [CleanerCategorySection] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var itemsByCategory: [CleanerCategoryID: [CleanerItem]] = [:]
        var noticesByCategory: [CleanerCategoryID: String] = [:]

        // Track paths already covered by specialized rules so dynamic ~/Library/Caches discovery doesn't double-count
        var claimedNormalizedPaths = Set<String>()

        // 1. Evaluate curated static rules
        onProgress("正在扫描浏览器与开发者工具缓存…")
        for rule in staticRules {
            var existingPaths: [String] = []
            var totalBytes: UInt64 = 0
            var totalFiles = 0

            for rel in rule.relativePaths {
                let abs = URL(fileURLWithPath: home).appendingPathComponent(rel).standardizedFileURL.path
                guard isPathAllowedForRule(abs, home: home), fm.fileExists(atPath: abs) else { continue }
                claimedNormalizedPaths.insert(abs)
                // Special case: ~/Library/Logs excludes DiagnosticReports (handled by its own rule)
                let excludeSubpaths: Set<String> = (rule.id == "sys.userLogs")
                    ? [URL(fileURLWithPath: home).appendingPathComponent("Library/Logs/DiagnosticReports").standardizedFileURL.path]
                    : []
                let stats = measureDirectoryOrFile(atPath: abs, excludingPaths: excludeSubpaths)
                if stats.bytes > 0 {
                    existingPaths.append(abs)
                    totalBytes &+= stats.bytes
                    totalFiles += stats.files
                }
            }

            guard totalBytes >= minDisplayBytes, !existingPaths.isEmpty else { continue }

            let runningName = rule.relatedBundleIDs.compactMap { runningApps[$0.lowercased()] }.first
            let defaultSel = rule.safety.defaultSelected && (runningName == nil)

            let item = CleanerItem(
                id: rule.id,
                category: rule.category,
                title: rule.title,
                detail: rule.detail,
                paths: existingPaths,
                byteSize: totalBytes,
                fileCount: totalFiles,
                safety: rule.safety,
                deletionAction: rule.action,
                runningAppName: runningName,
                modifiedAt: nil,
                isSelected: defaultSel
            )
            itemsByCategory[rule.category, default: []].append(item)
        }

        // 2. Conservative Uninstalled App Leftovers scan (runs BEFORE dynamic ~/Library/Caches so orphans aren't double-counted)
        onProgress("正在比对本机应用并检测已卸载软件残留…")
        let leftoverItems = scanUninstalledAppLeftovers(
            home: home,
            runningApps: runningApps,
            claimedPaths: &claimedNormalizedPaths
        )
        if !leftoverItems.isEmpty {
            itemsByCategory[.appLeftovers, default: []].append(contentsOf: leftoverItems)
        }

        // 3. Dynamic discovery of remaining user app caches under ~/Library/Caches (skipping Apple/protected/already claimed)
        onProgress("正在扫描 ~/Library/Caches 应用缓存…")
        let userCachesDir = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches").standardizedFileURL
        if let entries = try? fm.contentsOfDirectory(
            at: userCachesDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            for entryURL in entries {
                let path = entryURL.standardizedFileURL.path
                let name = entryURL.lastPathComponent
                guard !claimedNormalizedPaths.contains(path),
                      !isProtectedCacheName(name),
                      isPathAllowedForRule(path, home: home) else {
                    continue
                }
                // Skip if a child inside this directory was already claimed (e.g., ~/Library/Caches/Google/Chrome)
                let hasClaimedChild = claimedNormalizedPaths.contains { $0.hasPrefix(path + "/") }
                if hasClaimedChild { continue }

                let rv = try? entryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if rv?.isSymbolicLink == true { continue }

                let stats = measureDirectoryOrFile(atPath: path)
                guard stats.bytes >= minDisplayBytes else { continue }

                let friendlyName = resolveFriendlyAppName(forCacheFolder: name)
                let runningName = runningApps[name.lowercased()]
                    ?? runningApps["name:\(friendlyName.lowercased())"]
                    ?? runningApps["name:\(name.lowercased())"]
                let item = CleanerItem(
                    id: "cache.user.\(name)",
                    category: .systemAndLogs,
                    title: "\(friendlyName) 缓存",
                    detail: "位于 ~/Library/Caches/\(name) 的应用缓存，删除后软件会自动重建",
                    paths: [path],
                    byteSize: stats.bytes,
                    fileCount: stats.files,
                    safety: .safe,
                    deletionAction: .deleteContents,
                    runningAppName: runningName,
                    modifiedAt: nil,
                    isSelected: runningName == nil
                )
                itemsByCategory[.systemAndLogs, default: []].append(item)
            }
        }

        // 3. Installers (.dmg, .pkg, .mpkg, .xip) in ~/Downloads & ~/Desktop (move to Trash, opt-in)
        onProgress("正在查找旧安装包与磁盘镜像…")
        let installerExts: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
        var claimedInstallerPaths = Set<String>()
        for folderName in ["Downloads", "Desktop"] {
            let folderURL = URL(fileURLWithPath: home).appendingPathComponent(folderName).standardizedFileURL
            guard let files = try? fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for fileURL in files {
                let ext = fileURL.pathExtension.lowercased()
                guard installerExts.contains(ext) else { continue }
                let rv = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey])
                if rv?.isSymbolicLink == true { continue }
                let size = UInt64(rv?.totalFileAllocatedSize ?? rv?.fileAllocatedSize ?? rv?.fileSize ?? 0)
                guard size >= minDisplayBytes else { continue }

                let path = fileURL.standardizedFileURL.path
                guard isPathAllowedForRule(path, home: home) else { continue }
                claimedInstallerPaths.insert(path)

                let folderLabel = (folderName == "Downloads") ? "下载" : "桌面"
                let modDate = rv?.contentModificationDate
                let item = CleanerItem(
                    id: "installer.\(path)",
                    category: .installers,
                    title: fileURL.lastPathComponent,
                    detail: "位于「\(folderLabel)」的 .\(ext) 安装包，勾选清理后将安全移至废纸篓",
                    paths: [path],
                    byteSize: size,
                    fileCount: 1,
                    safety: .review,
                    deletionAction: .moveToTrash,
                    runningAppName: nil,
                    modifiedAt: modDate,
                    isSelected: false
                )
                itemsByCategory[.installers, default: []].append(item)
            }
        }

        // 4. Trash (~/.Trash) — handles TCC permission gracefully
        onProgress("正在检查废纸篓…")
        let trashURL = URL(fileURLWithPath: home).appendingPathComponent(".Trash").standardizedFileURL
        do {
            let trashEntries = try fm.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey],
                options: []
            )
            var trashTotalBytes: UInt64 = 0
            var trashTotalFiles = 0
            var trashPaths: [String] = []

            for entry in trashEntries {
                let p = entry.standardizedFileURL.path
                guard isPathAllowedForRule(p, home: home) else { continue }
                let stats = measureDirectoryOrFile(atPath: p)
                trashTotalBytes &+= stats.bytes
                trashTotalFiles += max(1, stats.files)
                trashPaths.append(p)
            }

            if !trashPaths.isEmpty {
                let item = CleanerItem(
                    id: "trash.user",
                    category: .trash,
                    title: "废纸篓中共有 \(trashEntries.count) 个项目",
                    detail: "清空后将永久删除废纸篓中的文件并立即释放磁盘空间",
                    paths: trashPaths,
                    byteSize: trashTotalBytes,
                    fileCount: trashTotalFiles,
                    safety: .review,
                    deletionAction: .emptyTrashItem,
                    runningAppName: nil,
                    modifiedAt: nil,
                    isSelected: false
                )
                itemsByCategory[.trash, default: []].append(item)
            }
        } catch {
            // macOS TCC protects ~/.Trash unless Full Disk Access is granted
            noticesByCategory[.trash] = "macOS 隐私保护限制直接读取废纸篓，可授予「完全磁盘访问权限」或在访达中手动清空。"
        }

        // 5. Large files (>= 100 MB) in ~/Downloads (excluding already listed installers; move to Trash, opt-in)
        onProgress("正在查找下载目录中的大文件…")
        let downloadsURL = URL(fileURLWithPath: home).appendingPathComponent("Downloads").standardizedFileURL
        if let files = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in files {
                let path = fileURL.standardizedFileURL.path
                guard !claimedInstallerPaths.contains(path), isPathAllowedForRule(path, home: home) else { continue }
                let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey])
                guard rv?.isRegularFile == true, rv?.isSymbolicLink != true else { continue }
                let size = UInt64(rv?.totalFileAllocatedSize ?? rv?.fileAllocatedSize ?? rv?.fileSize ?? 0)
                guard size >= largeFileThresholdBytes else { continue }

                let item = CleanerItem(
                    id: "large.\(path)",
                    category: .largeDownloads,
                    title: fileURL.lastPathComponent,
                    detail: "位于「下载」的大文件，勾选后将安全移至废纸篓（可随时放回原处）",
                    paths: [path],
                    byteSize: size,
                    fileCount: 1,
                    safety: .review,
                    deletionAction: .moveToTrash,
                    runningAppName: nil,
                    modifiedAt: rv?.contentModificationDate,
                    isSelected: false
                )
                itemsByCategory[.largeDownloads, default: []].append(item)
            }
        }

        // Sort items inside each category by byteSize descending
        var result: [CleanerCategorySection] = []
        for cat in CleanerCategoryID.allCases {
            let sorted = (itemsByCategory[cat] ?? []).sorted { $0.byteSize > $1.byteSize }
            let notice = noticesByCategory[cat]
            if !sorted.isEmpty || notice != nil {
                result.append(CleanerCategorySection(id: cat, items: sorted, permissionNotice: notice))
            }
        }
        return result
    }

    // MARK: - Safe Execution Engine

    static func executeCleanup(
        items: [CleanerItem],
        runningBundleIDs: Set<String> = [],
        onProgress: @escaping @Sendable (String) -> Void
    ) -> CleanupReport {
        let start = ProcessInfo.processInfo.systemUptime
        let home = NSHomeDirectory()
        let fm = FileManager.default

        var recordsByCat: [CleanerCategoryID: [CleanupItemRecord]] = [:]
        var totalFreed: UInt64 = 0
        var totalFiles = 0
        var hadPermissionError = false

        for (idx, item) in items.enumerated() {
            onProgress("正在清理 (\(idx + 1)/\(items.count))：\(item.title)…")

            var itemFreed: UInt64 = 0
            var itemRemovedCount = 0
            var firstError: String? = nil

            for rawPath in item.paths {
                guard isPathSafeToMutate(rawPath, home: home) else {
                    firstError = "受保护路径已跳过"
                    continue
                }
                guard fm.fileExists(atPath: rawPath) else { continue }

                let url = URL(fileURLWithPath: rawPath)

                switch item.deletionAction {
                case .moveToTrash:
                    let before = measureDirectoryOrFile(atPath: rawPath)
                    do {
                        try fm.trashItem(at: url, resultingItemURL: nil)
                        itemFreed &+= before.bytes
                        itemRemovedCount += max(1, before.files)
                    } catch let err as NSError {
                        if err.code == NSFileWriteNoPermissionError || err.code == NSFileReadNoPermissionError {
                            hadPermissionError = true
                            firstError = "缺少系统权限"
                        } else {
                            firstError = err.localizedDescription
                        }
                    }

                case .emptyTrashItem:
                    let before = measureDirectoryOrFile(atPath: rawPath)
                    do {
                        try fm.removeItem(at: url)
                        itemFreed &+= before.bytes
                        itemRemovedCount += max(1, before.files)
                    } catch let err as NSError {
                        if err.code == NSFileWriteNoPermissionError || err.code == NSFileReadNoPermissionError {
                            hadPermissionError = true
                            firstError = "受系统保护或文件占用中"
                        } else {
                            firstError = err.localizedDescription
                        }
                    }

                case .deleteContents:
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: rawPath, isDirectory: &isDir) else { continue }

                    if !isDir.boolValue {
                        let before = measureDirectoryOrFile(atPath: rawPath)
                        do {
                            try fm.removeItem(at: url)
                            itemFreed &+= before.bytes
                            itemRemovedCount += 1
                        } catch let err as NSError {
                            if err.code == NSFileWriteNoPermissionError || err.code == NSFileReadNoPermissionError {
                                hadPermissionError = true
                                firstError = "部分文件受系统保护或正在使用"
                            } else if firstError == nil {
                                firstError = err.localizedDescription
                            }
                        }
                        continue
                    }

                    // Delete directory children while keeping the cache container directory intact
                    let excludeSubpaths: Set<String> = (item.id == "sys.userLogs")
                        ? [URL(fileURLWithPath: home).appendingPathComponent("Library/Logs/DiagnosticReports").standardizedFileURL.path]
                        : []

                    guard let children = try? fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: []
                    ) else {
                        hadPermissionError = true
                        firstError = "无权访问该目录"
                        continue
                    }

                    for child in children {
                        let childPath = child.standardizedFileURL.path
                        if excludeSubpaths.contains(childPath) { continue }
                        if item.id == "sys.savedAppState" {
                            let nameLower = child.lastPathComponent.lowercased()
                            if nameLower.hasSuffix(".savedstate") {
                                let bid = String(nameLower.dropLast(".savedstate".count))
                                if runningBundleIDs.contains(bid) { continue }
                            }
                        }
                        guard isPathSafeToMutate(childPath, home: home) else { continue }

                        let childStats = measureDirectoryOrFile(atPath: childPath)
                        do {
                            try fm.removeItem(at: child)
                            itemFreed &+= childStats.bytes
                            itemRemovedCount += max(1, childStats.files)
                        } catch let err as NSError {
                            if err.code == NSFileWriteNoPermissionError || err.code == NSFileReadNoPermissionError {
                                hadPermissionError = true
                                if firstError == nil {
                                    firstError = "部分文件被系统或正在运行的软件占用"
                                }
                            } else if firstError == nil {
                                firstError = "部分项目无法删除"
                            }
                        }
                    }
                }
            }

            totalFreed &+= itemFreed
            totalFiles += itemRemovedCount

            let record = CleanupItemRecord(
                id: item.id,
                category: item.category,
                title: item.title,
                freedBytes: itemFreed,
                removedFileCount: itemRemovedCount,
                action: item.deletionAction,
                skippedReason: firstError
            )
            recordsByCat[item.category, default: []].append(record)
        }

        var summaries: [CleanupCategorySummary] = []
        for cat in CleanerCategoryID.allCases {
            guard let records = recordsByCat[cat], !records.isEmpty else { continue }
            let cleaned = records.filter { $0.freedBytes > 0 || $0.skippedReason == nil }
            let skipped = records.filter { $0.freedBytes == 0 && $0.skippedReason != nil }
            let freed = records.reduce(0) { $0 &+ $1.freedBytes }
            summaries.append(
                CleanupCategorySummary(
                    id: cat,
                    freedBytes: freed,
                    cleanedItems: cleaned,
                    skippedItems: skipped
                )
            )
        }

        let elapsed = max(0.05, ProcessInfo.processInfo.systemUptime - start)
        return CleanupReport(
            finishedAt: Date(),
            durationSeconds: elapsed,
            totalFreedBytes: totalFreed,
            totalRemovedFiles: totalFiles,
            categorySummaries: summaries,
            hadPermissionRestrictions: hadPermissionError
        )
    }

    // MARK: - APFS Real Allocated Size Measurement & Path Safety

    private static func measureDirectoryOrFile(
        atPath path: String,
        excludingPaths: Set<String> = []
    ) -> (bytes: UInt64, files: Int) {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]

        guard let topRV = try? url.resourceValues(forKeys: Set(keys)) else {
            return (0, 0)
        }
        if topRV.isSymbolicLink == true {
            return (0, 0)
        }
        if topRV.isRegularFile == true {
            let sz = UInt64(topRV.totalFileAllocatedSize ?? topRV.fileAllocatedSize ?? topRV.fileSize ?? 0)
            return (sz, 1)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return (0, 0)
        }

        var totalBytes: UInt64 = 0
        var totalFiles = 0

        for case let fileURL as URL in enumerator {
            if !excludingPaths.isEmpty {
                let p = fileURL.standardizedFileURL.path
                if excludingPaths.contains(p) {
                    enumerator.skipDescendants()
                    continue
                }
            }
            guard let rv = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if rv.isSymbolicLink == true {
                if rv.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if rv.isRegularFile == true {
                let sz = UInt64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0)
                totalBytes &+= sz
                totalFiles += 1
            }
        }
        return (totalBytes, totalFiles)
    }

    private static func isProtectedCacheName(_ name: String) -> Bool {
        if protectedCacheExactNames.contains(name) { return true }
        let lower = name.lowercased()
        for prefix in protectedCacheEntryPrefixes {
            if lower.hasPrefix(prefix.lowercased()) {
                return true
            }
        }
        return false
    }

    /// Strict home-directory containment + blocklist guard (evaluated before scanning AND before deleting)
    private static func isPathAllowedForRule(_ path: String, home: String) -> Bool {
        let stdHome = URL(fileURLWithPath: home).standardizedFileURL.path
        let stdPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard stdPath.hasPrefix(stdHome + "/"), stdPath != stdHome else {
            return false
        }
        for frag in forbiddenAbsoluteFragments {
            if stdPath.contains(frag) {
                return false
            }
        }
        return true
    }

    /// Extra strict symlink-resolved check executed immediately before any FileManager mutation
    private static func isPathSafeToMutate(_ path: String, home: String) -> Bool {
        guard isPathAllowedForRule(path, home: home) else { return false }
        let stdHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.hasPrefix(stdHome + "/"), resolved != stdHome else {
            return false
        }
        // Never allow deleting top-level home folders directly (e.g. ~/Library, ~/Downloads, ~/Desktop)
        let relative = String(resolved.dropFirst(stdHome.count + 1))
        if !relative.contains("/") {
            return false
        }
        for frag in forbiddenAbsoluteFragments {
            if resolved.contains(frag) {
                return false
            }
        }
        return true
    }

    private static func resolveFriendlyAppName(forCacheFolder folderName: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folderName) {
            let base = appURL.deletingPathExtension().lastPathComponent
            if !base.isEmpty { return base }
        }
        if folderName.contains(".") {
            let parts = folderName.split(separator: ".")
            if let last = parts.last, last.count >= 2 {
                return String(last)
            }
        }
        return folderName
    }

    // MARK: - Conservative Uninstalled App Leftovers Scanner (Pearcleaner-style)

    /// Scans strict reverse-DNS bundle directories under ~/Library/* and cross-checks them against:
    /// 1) All installed .app bundles (including Helpers/LoginItems) and Plug-Ins/PreferencePanes
    /// 2) All currently running apps
    /// 3) macOS LaunchServices (`NSWorkspace.shared.urlForApplication(withBundleIdentifier:) == nil`)
    /// Every detected leftover is marked `.review` (unchecked by default) and removed via `.moveToTrash`.
    private static func scanUninstalledAppLeftovers(
        home: String,
        runningApps: [String: String],
        claimedPaths: inout Set<String>
    ) -> [CleanerItem] {
        let fm = FileManager.default
        let installedBundleIDs = collectInstalledBundleIDs(home: home, runningApps: runningApps)

        let scanLocations: [(relDir: String, label: String, stripSuffix: String?)] = [
            ("Library/Application Support", "Application Support", nil),
            ("Library/Caches", "Caches", nil),
            ("Library/Containers", "容器", nil),
            ("Library/HTTPStorages", "HTTP 缓存", nil),
            ("Library/WebKit", "WebKit", nil),
            ("Library/Saved Application State", "窗口快照", ".savedState")
        ]

        // Group candidate paths by normalized uninstalled bundleID
        var pathsByBundleID: [String: [(path: String, label: String, bytes: UInt64, files: Int)]] = [:]

        for loc in scanLocations {
            let dirURL = URL(fileURLWithPath: home).appendingPathComponent(loc.relDir).standardizedFileURL
            guard let entries = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entryURL in entries {
                let path = entryURL.standardizedFileURL.path
                guard !claimedPaths.contains(path), isPathAllowedForRule(path, home: home) else { continue }
                let rv = try? entryURL.resourceValues(forKeys: [.isSymbolicLinkKey])
                if rv?.isSymbolicLink == true { continue }

                var rawName = entryURL.lastPathComponent
                if let suffix = loc.stripSuffix {
                    guard rawName.hasSuffix(suffix) else { continue }
                    rawName = String(rawName.dropLast(suffix.count))
                }

                let bidLower = rawName.lowercased()
                guard isStrictReverseDNSBundleID(bidLower),
                      !isProtectedLeftoverBundleID(bidLower),
                      !isBundleIDInstalledOrRelated(bidLower, installed: installedBundleIDs) else {
                    continue
                }

                // Final LaunchServices verification: if macOS knows ANY app anywhere on disk with this ID, keep it!
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawName) != nil {
                    continue
                }

                let stats = measureDirectoryOrFile(atPath: path)
                guard stats.bytes > 0 else { continue }

                pathsByBundleID[bidLower, default: []].append((path, loc.label, stats.bytes, stats.files))
            }
        }

        // Also pair matching ~/Library/Preferences/<bid>.plist ONLY for bundle IDs already confirmed as leftovers
        let prefsDir = URL(fileURLWithPath: home).appendingPathComponent("Library/Preferences").standardizedFileURL
        for bidLower in Array(pathsByBundleID.keys) {
            if let entries = try? fm.contentsOfDirectory(at: prefsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for entryURL in entries where entryURL.pathExtension.lowercased() == "plist" {
                    let stem = entryURL.deletingPathExtension().lastPathComponent.lowercased()
                    if stem == bidLower {
                        let p = entryURL.standardizedFileURL.path
                        if isPathAllowedForRule(p, home: home) {
                            let stats = measureDirectoryOrFile(atPath: p)
                            pathsByBundleID[bidLower, default: []].append((p, "Preferences", stats.bytes, max(1, stats.files)))
                        }
                    }
                }
            }
        }

        var items: [CleanerItem] = []
        for (bidLower, entries) in pathsByBundleID {
            let totalBytes = entries.reduce(UInt64(0)) { $0 &+ $1.bytes }
            let totalFiles = entries.reduce(0) { $0 + $1.files }
            // Keep threshold at 128 KB for app leftovers so real orphan folders/containers show up cleanly
            guard totalBytes >= 128 * 1024 else { continue }

            let allPaths = entries.map(\.path)
            for p in allPaths {
                claimedPaths.insert(p)
            }

            let labels = Array(NSOrderedSet(array: entries.map(\.label))) as? [String] ?? []
            let friendly = resolveFriendlyAppName(forCacheFolder: bidLower)
            let detail = "本机未找到「\(bidLower)」对应程序（含 \(labels.joined(separator: "、")) 共 \(allPaths.count) 处），勾选后将安全移至废纸篓"

            items.append(
                CleanerItem(
                    id: "leftover.\(bidLower)",
                    category: .appLeftovers,
                    title: "\(friendly) 残留 (\(bidLower))",
                    detail: detail,
                    paths: allPaths,
                    byteSize: totalBytes,
                    fileCount: totalFiles,
                    safety: .review,
                    deletionAction: .moveToTrash,
                    runningAppName: nil,
                    modifiedAt: nil,
                    isSelected: false
                )
            )
        }

        return items.sorted { $0.byteSize > $1.byteSize }
    }

    private static func collectInstalledBundleIDs(home: String, runningApps: [String: String]) -> Set<String> {
        let fm = FileManager.default
        var ids = Set<String>()

        for key in runningApps.keys where !key.hasPrefix("name:") {
            ids.insert(key.lowercased())
        }

        let appRoots: [(path: String, maxDepth: Int)] = [
            ("/Applications", 2),
            ("/System/Applications", 2),
            ("/System/Library/CoreServices", 1),
            (URL(fileURLWithPath: home).appendingPathComponent("Applications").path, 2),
            ("/Library/PreferencePanes", 1),
            (URL(fileURLWithPath: home).appendingPathComponent("Library/PreferencePanes").path, 1),
            ("/Library/Audio/Plug-Ins", 2),
            (URL(fileURLWithPath: home).appendingPathComponent("Library/Audio/Plug-Ins").path, 2)
        ]

        func scanBundles(in dirURL: URL, depth: Int, maxDepth: Int) {
            guard depth <= maxDepth,
                  let entries = try? fm.contentsOfDirectory(
                    at: dirURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                  ) else { return }

            for url in entries {
                let ext = url.pathExtension.lowercased()
                if ext == "app" || ext == "prefpane" || ext == "component" || ext == "vst3" || ext == "driver" || ext == "appex" {
                    if let bid = Bundle(url: url)?.bundleIdentifier?.lowercased(), !bid.isEmpty {
                        ids.insert(bid)
                    }
                    // Also register embedded LoginItems & Helpers so helper caches aren't falsely flagged
                    for sub in ["Contents/Library/LoginItems", "Contents/Helpers", "Contents/PlugIns"] {
                        let subURL = url.appendingPathComponent(sub)
                        if let subEntries = try? fm.contentsOfDirectory(at: subURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                            for subItem in subEntries {
                                if let subBid = Bundle(url: subItem)?.bundleIdentifier?.lowercased(), !subBid.isEmpty {
                                    ids.insert(subBid)
                                }
                            }
                        }
                    }
                } else if depth < maxDepth {
                    let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if rv?.isDirectory == true && rv?.isSymbolicLink != true {
                        scanBundles(in: url, depth: depth + 1, maxDepth: maxDepth)
                    }
                }
            }
        }

        for root in appRoots {
            scanBundles(in: URL(fileURLWithPath: root.path), depth: 1, maxDepth: root.maxDepth)
        }
        return ids
    }

    private static func isStrictReverseDNSBundleID(_ lower: String) -> Bool {
        let parts = lower.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        let knownTLDs: Set<String> = ["com", "org", "net", "io", "cn", "app", "dev", "co", "me", "de", "jp", "uk", "edu", "ai", "ch", "fr", "nl", "ru", "im", "tv", "cc", "xyz", "pro", "so", "us", "ca", "hk", "tw"]
        guard let first = parts.first, knownTLDs.contains(String(first)) else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    private static func isProtectedLeftoverBundleID(_ lower: String) -> Bool {
        for prefix in protectedLeftoverPrefixes {
            if lower.hasPrefix(prefix) { return true }
        }
        return false
    }

    private static func isBundleIDInstalledOrRelated(_ candidate: String, installed: Set<String>) -> Bool {
        if installed.contains(candidate) { return true }
        // Check helper/extension prefix relationship in both directions (e.g. com.foo.bar.ShipIt <-> com.foo.bar)
        for bid in installed {
            if candidate.hasPrefix(bid + ".") || bid.hasPrefix(candidate + ".") {
                return true
            }
        }
        return false
    }

    // MARK: - Native Zero-Subprocess Startup / Login Items Scanner & User Toggle

    static func disabledVaultURL(home: String) -> URL {
        URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/YOMO/DisabledLaunchAgents", isDirectory: true)
            .standardizedFileURL
    }

    static func scanStartupItems(
        runningSnap: (bundleIDs: Set<String>, executablePaths: Set<String>, executableNames: Set<String>)
    ) -> [StartupItemInfo] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let uid = getuid()
        var results: [StartupItemInfo] = []

        // Read macOS launchd's native disabled override plists (world-readable, zero subprocess)
        let userDisabledOverrides = readLaunchdDisabledOverrides(at: "/var/db/com.apple.xpc.launchd/disabled.\(uid).plist")
        let systemDisabledOverrides = readLaunchdDisabledOverrides(at: "/var/db/com.apple.xpc.launchd/disabled.plist")

        let userAgentsDir = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents").standardizedFileURL.path
        let vaultDir = disabledVaultURL(home: home).path

        let plistDirs: [(path: String, scope: StartupItemScope, canToggle: Bool, canTrash: Bool, isVault: Bool)] = [
            (userAgentsDir, .userLaunchAgent, true, true, false),
            (vaultDir, .userLaunchAgent, true, true, true),
            ("/Library/LaunchAgents", .globalLaunchAgent, false, false, false),
            ("/Library/LaunchDaemons", .globalLaunchDaemon, false, false, false)
        ]

        var seenLabelsInUserScope = Set<String>()

        for dirSpec in plistDirs {
            let dirURL = URL(fileURLWithPath: dirSpec.path)
            guard let files = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for fileURL in files where fileURL.pathExtension.lowercased() == "plist" {
                guard let data = try? Data(contentsOf: fileURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                    continue
                }

                let label = (plist["Label"] as? String) ?? fileURL.deletingPathExtension().lastPathComponent
                if dirSpec.scope == .userLaunchAgent {
                    let key = label.lowercased()
                    if seenLabelsInUserScope.contains(key) { continue }
                    seenLabelsInUserScope.insert(key)
                }

                let progArgs = plist["ProgramArguments"] as? [String]
                let rawProgram = (plist["Program"] as? String) ?? progArgs?.first
                let expandedExec: String? = rawProgram.map { p in
                    if p.hasPrefix("~/") {
                        return home + String(p.dropFirst(1))
                    }
                    return p
                }

                let runAtLoad = (plist["RunAtLoad"] as? Bool) ?? false
                let keepAlive: Bool = {
                    if let b = plist["KeepAlive"] as? Bool { return b }
                    if let d = plist["KeepAlive"] as? [String: Any], !d.isEmpty { return true }
                    return false
                }()
                let disabledInPlist = (plist["Disabled"] as? Bool) ?? false

                let overrides = (dirSpec.scope == .userLaunchAgent) ? userDisabledOverrides : systemDisabledOverrides
                let isEnabled: Bool = {
                    if dirSpec.isVault { return false }
                    if let ov = overrides[label] { return !ov }
                    return !disabledInPlist
                }()

                let isOrphaned: Bool = {
                    guard let exec = expandedExec, !exec.isEmpty else { return false }
                    guard exec.hasPrefix("/") else { return false }
                    return !fm.fileExists(atPath: exec)
                }()

                let assocBundles = (plist["AssociatedBundleIdentifiers"] as? [String])
                    ?? ((plist["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? [])

                let isRunning: Bool = {
                    if dirSpec.isVault { return false }
                    if runningSnap.bundleIDs.contains(label.lowercased()) { return true }
                    for b in assocBundles where runningSnap.bundleIDs.contains(b.lowercased()) {
                        return true
                    }
                    if let exec = expandedExec {
                        let lowerExec = URL(fileURLWithPath: exec).standardizedFileURL.path.lowercased()
                        if runningSnap.executablePaths.contains(lowerExec) { return true }
                        let baseName = URL(fileURLWithPath: exec).lastPathComponent.lowercased()
                        if runningSnap.executableNames.contains(baseName) { return true }
                    }
                    return false
                }()

                let (displayName, appBundlePath) = resolveStartupIdentity(
                    label: label,
                    executablePath: expandedExec,
                    associatedBundles: assocBundles
                )

                results.append(
                    StartupItemInfo(
                        id: "\(dirSpec.scope.rawValue)::\(label)",
                        label: label,
                        displayName: displayName,
                        scope: dirSpec.scope,
                        sourcePath: fileURL.standardizedFileURL.path,
                        executablePath: expandedExec,
                        appBundlePath: appBundlePath,
                        runAtLoad: runAtLoad,
                        keepAlive: keepAlive,
                        isEnabled: isEnabled,
                        isStoredInDisabledVault: dirSpec.isVault,
                        isRunning: isRunning,
                        isOrphanedBinary: isOrphaned,
                        canToggleDirectly: dirSpec.canToggle && !isOrphaned,
                        canMoveToTrash: dirSpec.canTrash
                    )
                )
            }
        }

        // Also inspect embedded modern LoginItems inside /Applications and ~/Applications (read-only awareness)
        let appDirs = ["/Applications", URL(fileURLWithPath: home).appendingPathComponent("Applications").path]
        for appDir in appDirs {
            guard let apps = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: appDir),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for appURL in apps where appURL.pathExtension.lowercased() == "app" {
                let loginItemsDir = appURL.appendingPathComponent("Contents/Library/LoginItems")
                guard let helpers = try? fm.contentsOfDirectory(at: loginItemsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                    continue
                }
                let parentName = appURL.deletingPathExtension().lastPathComponent
                for helperURL in helpers where helperURL.pathExtension.lowercased() == "app" {
                    let helperBundle = Bundle(url: helperURL)
                    let bid = helperBundle?.bundleIdentifier ?? helperURL.deletingPathExtension().lastPathComponent
                    let isRunning = runningSnap.bundleIDs.contains(bid.lowercased())
                    let isEnabled = userDisabledOverrides[bid].map { !$0 } ?? isRunning
                    results.append(
                        StartupItemInfo(
                            id: "loginItem::\(helperURL.path)",
                            label: bid,
                            displayName: "\(parentName)（内嵌登录助手）",
                            scope: .appLoginItem,
                            sourcePath: helperURL.standardizedFileURL.path,
                            executablePath: helperBundle?.executablePath,
                            appBundlePath: appURL.standardizedFileURL.path,
                            runAtLoad: true,
                            keepAlive: false,
                            isEnabled: isEnabled,
                            isStoredInDisabledVault: false,
                            isRunning: isRunning,
                            isOrphanedBinary: false,
                            canToggleDirectly: false,
                            canMoveToTrash: false
                        )
                    )
                }
            }
        }

        // Sort: user-toggleable first (or orphaned zombies), then enabled/running, then alphabetical
        return results.sorted { a, b in
            if a.isOrphanedBinary != b.isOrphanedBinary { return a.isOrphanedBinary }
            if a.canToggleDirectly != b.canToggleDirectly { return a.canToggleDirectly }
            if a.isEnabled != b.isEnabled { return a.isEnabled }
            if a.isRunning != b.isRunning { return a.isRunning }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Explicit user-triggered toggle for a user-owned LaunchAgent (never called in polling).
    static func toggleUserLaunchAgent(_ item: StartupItemInfo, enabled: Bool) -> (ok: Bool, message: String) {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let uid = getuid()
        let domain = "gui/\(uid)"
        let activeDir = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents", isDirectory: true).standardizedFileURL
        let vaultDir = disabledVaultURL(home: home)
        let currentURL = URL(fileURLWithPath: item.sourcePath).standardizedFileURL
        let fileName = currentURL.lastPathComponent

        if enabled {
            let destURL = activeDir.appendingPathComponent(fileName)
            do {
                try fm.createDirectory(at: activeDir, withIntermediateDirectories: true)
                if currentURL.path != destURL.path, fm.fileExists(atPath: currentURL.path) {
                    if fm.fileExists(atPath: destURL.path) {
                        try fm.removeItem(at: destURL)
                    }
                    try fm.moveItem(at: currentURL, to: destURL)
                }
                _ = runLaunchctl(["enable", "\(domain)/\(item.label)"])
                _ = runLaunchctl(["bootstrap", domain, destURL.path])
                return (true, "已开启用户启动项「\(item.displayName)」，已恢复并立即生效")
            } catch {
                return (false, "开启「\(item.displayName)」失败：\(error.localizedDescription)")
            }
        } else {
            let destURL = vaultDir.appendingPathComponent(fileName)
            do {
                try fm.createDirectory(at: vaultDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                _ = runLaunchctl(["disable", "\(domain)/\(item.label)"])
                if currentURL.path.hasPrefix(activeDir.path + "/") {
                    _ = runLaunchctl(["bootout", domain, currentURL.path])
                    if fm.fileExists(atPath: destURL.path) {
                        try fm.removeItem(at: destURL)
                    }
                    try fm.moveItem(at: currentURL, to: destURL)
                }
                return (true, "已关闭用户启动项「\(item.displayName)」，配置已无损暂存，随时可重新开启")
            } catch {
                return (false, "关闭「\(item.displayName)」失败：\(error.localizedDescription)")
            }
        }
    }

    private static func runLaunchctl(_ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            return -1
        }
    }

    private static func readLaunchdDisabledOverrides(at path: String) -> [String: Bool] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return [:]
        }
        var result: [String: Bool] = [:]
        for (k, v) in dict {
            if let b = v as? Bool {
                result[k] = b
            }
        }
        return result
    }

    private static func resolveStartupIdentity(
        label: String,
        executablePath: String?,
        associatedBundles: [String]
    ) -> (displayName: String, appBundlePath: String?) {
        for bid in associatedBundles {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                return (appURL.deletingPathExtension().lastPathComponent, appURL.standardizedFileURL.path)
            }
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: label) {
            return (appURL.deletingPathExtension().lastPathComponent, appURL.standardizedFileURL.path)
        }
        if let exec = executablePath {
            let comps = URL(fileURLWithPath: exec).pathComponents
            if let idx = comps.firstIndex(where: { $0.hasSuffix(".app") }) {
                let appPath = NSString.path(withComponents: Array(comps.prefix(idx + 1)))
                let name = String(comps[idx].dropLast(4))
                return (name, FileManager.default.fileExists(atPath: appPath) ? appPath : nil)
            }
            let base = URL(fileURLWithPath: exec).lastPathComponent
            if !base.isEmpty { return (base, nil) }
        }
        return (resolveFriendlyAppName(forCacheFolder: label), nil)
    }
}

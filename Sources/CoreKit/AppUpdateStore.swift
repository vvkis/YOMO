import Foundation
import AppKit
import SwiftUI
import CryptoKit

// MARK: - Models

public struct AppReleaseInfo: Equatable, Sendable {
    public let tagName: String
    public let version: String
    public let title: String
    public let notes: String
    public let publishedAt: Date?
    public let htmlURL: URL
    public let assetName: String
    public let assetDownloadURL: URL
    public let assetSizeBytes: Int64
    public let checksumsURL: URL?

    public var displayVersion: String {
        version.hasPrefix("v") || version.hasPrefix("V") ? version : "v\(version)"
    }
}

public enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(AppReleaseInfo)
    case downloading(AppReleaseInfo, progress: Double, downloadedBytes: Int64, totalBytes: Int64)
    case verifying(AppReleaseInfo)
    case readyToInstall(AppReleaseInfo, stagedAppPath: String, stagingRootPath: String, sha256Verified: Bool)
    case installing(AppReleaseInfo)
    case failed(String)

    public var availableRelease: AppReleaseInfo? {
        switch self {
        case .available(let r),
             .downloading(let r, _, _, _),
             .verifying(let r),
             .readyToInstall(let r, _, _, _),
             .installing(let r):
            return r
        default:
            return nil
        }
    }

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing:
            return true
        default:
            return false
        }
    }
}

// MARK: - GitHub API Decodables

private struct GitHubReleasePayload: Decodable, Sendable {
    let tag_name: String
    let name: String?
    let body: String?
    let draft: Bool?
    let prerelease: Bool?
    let published_at: String?
    let html_url: String
    let assets: [GitHubAssetPayload]
}

private struct GitHubAssetPayload: Decodable, Sendable {
    let name: String
    let size: Int64
    let browser_download_url: String
}

// MARK: - Download Delegate Bridge

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var lastReportTime: TimeInterval = 0
    private let onProgress: @Sendable (Double, Int64, Int64) -> Void
    private let onFinished: @Sendable (Result<URL, Error>) -> Void
    private var didFinish = false

    init(
        onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void,
        onFinished: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onFinished = onFinished
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        let shouldReport = (now - lastReportTime) >= 0.10 || totalBytesWritten == totalBytesExpectedToWrite
        if shouldReport {
            lastReportTime = now
        }
        lock.unlock()
        guard shouldReport else { return }

        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        } else {
            progress = 0.0
        }
        onProgress(progress, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            finishOnce(.failure(NSError(
                domain: "YOMOUpdate",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "下载安装包失败（HTTP \(http.statusCode)）"]
            )))
            return
        }

        // Move immediately out of URLSession's ephemeral temp location before this callback returns
        let stageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YOMO-Update-\(UUID().uuidString)", isDirectory: true)
        let fileName = downloadTask.response?.suggestedFilename ?? "YOMO-update.dmg"
        let destURL = stageDir.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destURL)
            finishOnce(.success(destURL))
        } catch {
            finishOnce(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finishOnce(.failure(error))
        }
    }

    private func finishOnce(_ result: Result<URL, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        onFinished(result)
    }
}

// MARK: - AppUpdateStore

/// Native, zero-dependency GitHub Releases updater for YOMO.
/// - Checks `vvkis/YOMO` releases via URLSession (manual or quiet once-per-24h check on launch; zero idle timers).
/// - Downloads `.dmg`/`.zip` with live progress and verifies SHA-256 via Apple CryptoKit against `SHA256SUMS.txt`.
/// - Performs an atomic in-place `.app` replacement and relaunch so all preferences (`com.yomo.suite`),
///   clipboard history, menu bar position, and Login Item registration are preserved seamlessly.
@MainActor
public final class AppUpdateStore: ObservableObject {
    public nonisolated static let githubRepo = "vvkis/YOMO"
    public nonisolated static let releasesPageURL = URL(string: "https://github.com/vvkis/YOMO/releases")!
    private nonisolated static let latestReleaseWebURL = URL(string: "https://github.com/vvkis/YOMO/releases/latest")!
    private nonisolated static let releasesAtomURL = URL(string: "https://github.com/vvkis/YOMO/releases.atom")!
    private nonisolated static let releaseAPIBaseURL = "https://api.github.com/repos/vvkis/YOMO/releases/tags/"
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    @AppStorage("updater.autoCheckEnabled") public var autoCheckEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("updater.lastCheckTimestamp") private var lastCheckTimestamp: Double = 0

    @Published public private(set) var state: AppUpdateState = .idle

    /// Optional hook invoked right before terminating for an in-place upgrade so modules flush state cleanly.
    public var onPrepareForUpgradeQuit: (() -> Void)?

    private var checkTask: Task<Void, Never>?
    private var downloadSession: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var activeStagingRootPath: String?
    private let workQueue = DispatchQueue(label: "com.yomo.updater.worker", qos: .userInitiated)

    public init() {}

    public var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.5.0"
    }

    public var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    public var displayCurrentVersion: String {
        "v\(currentVersion)"
    }

    public var hasUpdateAvailable: Bool {
        state.availableRelease != nil
    }

    public var lastCheckedText: String? {
        guard lastCheckTimestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: lastCheckTimestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Quiet Launch Check (Zero Idle Timers)

    public func scheduleLaunchCheckIfDue() {
        guard autoCheckEnabled else { return }
        let now = Date().timeIntervalSince1970
        guard (now - lastCheckTimestamp) >= Self.autoCheckInterval else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.autoCheckEnabled, case .idle = self.state else { return }
                self.checkForUpdates(userInitiated: false)
            }
        }
    }

    // MARK: - Check for Updates

    public func checkForUpdates(userInitiated: Bool = true) {
        guard !state.isBusy else { return }
        checkTask?.cancel()
        if userInitiated {
            state = .checking
        }

        let currentVer = currentVersion
        checkTask = Task { [weak self] in
            do {
                let release = try await Self.fetchLatestRelease(currentVersion: currentVer)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let now = Date()
                    self.lastCheckTimestamp = now.timeIntervalSince1970
                    if let release, Self.isVersion(release.version, newerThan: self.currentVersion) {
                        self.state = .available(release)
                    } else if userInitiated {
                        self.state = .upToDate(checkedAt: now)
                    } else {
                        self.state = .idle
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if userInitiated {
                        self.state = .failed(error.localizedDescription)
                    } else {
                        self.state = .idle
                    }
                }
            }
        }
    }

    // MARK: - Download & Verify

    public func downloadAvailableUpdate() {
        guard let release = state.availableRelease, !state.isBusy else { return }
        cleanupActiveStaging()
        state = .downloading(release, progress: 0, downloadedBytes: 0, totalBytes: release.assetSizeBytes)

        let delegate = UpdateDownloadDelegate(
            onProgress: { [weak self] progress, downloaded, total in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .downloading(let currentRelease, _, _, _) = self.state,
                       currentRelease.version == release.version {
                        let resolvedTotal = total > 0 ? total : release.assetSizeBytes
                        self.state = .downloading(release, progress: progress, downloadedBytes: downloaded, totalBytes: resolvedTotal)
                    }
                }
            },
            onFinished: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.downloadTask = nil
                    self.downloadSession?.finishTasksAndInvalidate()
                    self.downloadSession = nil

                    switch result {
                    case .failure(let err):
                        let nsErr = err as NSError
                        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                            self.state = .available(release)
                        } else {
                            self.state = .failed("下载更新失败：\(err.localizedDescription)")
                        }
                    case .success(let downloadedFileURL):
                        self.verifyAndStageDownloadedFile(downloadedFileURL, release: release)
                    }
                }
            }
        )

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        var req = URLRequest(url: release.assetDownloadURL)
        req.setValue("YOMO/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: req)
        self.downloadSession = session
        self.downloadTask = task
        task.resume()
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        if let release = state.availableRelease {
            state = .available(release)
        } else {
            state = .idle
        }
    }

    private func verifyAndStageDownloadedFile(_ downloadedFileURL: URL, release: AppReleaseInfo) {
        state = .verifying(release)
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.yomo.suite"
        let stageRoot = downloadedFileURL.deletingLastPathComponent()
        activeStagingRootPath = stageRoot.path

        workQueue.async { [weak self] in
            let outcome = Self.verifyAndExtract(
                archiveURL: downloadedFileURL,
                stageRoot: stageRoot,
                release: release,
                expectedBundleID: expectedBundleID
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch outcome {
                case .success(let staged):
                    self.state = .readyToInstall(
                        release,
                        stagedAppPath: staged.appURL.path,
                        stagingRootPath: stageRoot.path,
                        sha256Verified: staged.sha256Verified
                    )
                case .failure(let err):
                    try? FileManager.default.removeItem(at: stageRoot)
                    self.activeStagingRootPath = nil
                    self.state = .failed(err.localizedDescription)
                }
            }
        }
    }

    // MARK: - Atomic In-Place Upgrade & Relaunch

    public func installAndRelaunch() {
        guard case .readyToInstall(let release, let stagedAppPath, let stagingRootPath, _) = state else {
            return
        }

        let currentAppURL = Bundle.main.bundleURL.standardizedFileURL
        guard currentAppURL.pathExtension.lowercased() == "app" else {
            state = .failed("当前并非从 .app 应用包运行，请先打包 YOMO.app 后再使用自动升级。")
            return
        }
        guard FileManager.default.fileExists(atPath: stagedAppPath) else {
            state = .failed("暂存的新版本安装包已失效，请重新下载更新。")
            return
        }

        state = .installing(release)
        let parentDir = currentAppURL.deletingLastPathComponent().path
        let isWritable = FileManager.default.isWritableFile(atPath: parentDir)
            && FileManager.default.isWritableFile(atPath: currentAppURL.path)

        let pid = ProcessInfo.processInfo.processIdentifier
        let targetPath = currentAppURL.path

        if isWritable {
            guard launchInPlaceSwapHelper(
                oldPID: pid,
                stagedAppPath: stagedAppPath,
                targetAppPath: targetPath,
                stagingRootPath: stagingRootPath
            ) else {
                state = .failed("无法启动原地升级脚本，请点击「打开发布页」手动覆盖安装。")
                return
            }
            // Clear activeStagingRootPath so deinit/cleanup does not delete the staged bundle before the helper swaps it
            activeStagingRootPath = nil
            onPrepareForUpgradeQuit?()
            NSApp.terminate(nil)
        } else {
            // Non-writable /Applications (standard user): request one-time native macOS admin authorization
            workQueue.async { [weak self] in
                let ok = Self.launchPrivilegedSwapHelper(
                    oldPID: pid,
                    stagedAppPath: stagedAppPath,
                    targetAppPath: targetPath,
                    stagingRootPath: stagingRootPath
                )
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if ok {
                        self.activeStagingRootPath = nil
                        self.onPrepareForUpgradeQuit?()
                        NSApp.terminate(nil)
                    } else {
                        self.state = .readyToInstall(
                            release,
                            stagedAppPath: stagedAppPath,
                            stagingRootPath: stagingRootPath,
                            sha256Verified: true
                        )
                    }
                }
            }
        }
    }

    public func openReleasesPage() {
        let url = state.availableRelease?.htmlURL ?? Self.releasesPageURL
        NSWorkspace.shared.open(url)
    }

    public func resetErrorIfNeeded() {
        if case .failed = state {
            state = .idle
        }
    }

    public static func formatByteSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let mb = Double(bytes) / 1_000_000.0
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        return String(format: "%.0f KB", Double(bytes) / 1_000.0)
    }

    private func cleanupActiveStaging() {
        if let path = activeStagingRootPath {
            try? FileManager.default.removeItem(atPath: path)
            activeStagingRootPath = nil
        }
    }

    private struct GitHubWebLatestPayload: Decodable, Sendable {
        let tag_name: String?
    }

    // MARK: - Networking, SemVer, Checksum & Extraction Helpers

    /// Checks latest release using `github.com/<repo>/releases/latest` (NOT `api.github.com`),
    /// completely bypassing GitHub's strict 60 req/hr unauthenticated IP API rate limit on shared proxy IPs.
    /// Only fetches full metadata when a newer version is actually detected, with full web/Atom fallback.
    private nonisolated static func fetchLatestRelease(currentVersion: String) async throws -> AppReleaseInfo? {
        // 1. Lightweight rate-limit-free tag discovery via GitHub web endpoint
        var webReq = URLRequest(url: latestReleaseWebURL)
        webReq.timeoutInterval = 15
        webReq.setValue("application/json", forHTTPHeaderField: "Accept")
        webReq.setValue("YOMO/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (webData, webResp) = try await URLSession.shared.data(for: webReq)
        guard let http = webResp as? HTTPURLResponse else {
            throw NSError(domain: "YOMOUpdate", code: -1, userInfo: [NSLocalizedDescriptionKey: "网络响应异常，请稍后重试"])
        }
        if http.statusCode == 404 {
            throw NSError(domain: "YOMOUpdate", code: 404, userInfo: [NSLocalizedDescriptionKey: "GitHub 仓库暂未发布公开 Release 版本"])
        }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "YOMOUpdate", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "检查更新失败（HTTP \(http.statusCode)）"])
        }

        // Resolve tag from JSON payload first, falling back to redirected `/releases/tag/<tag>` URL
        let discoveredTag: String? = {
            if let decoded = try? JSONDecoder().decode(GitHubWebLatestPayload.self, from: webData),
               let tag = decoded.tag_name, !tag.isEmpty {
                return tag
            }
            if let finalURL = http.url {
                let comps = finalURL.pathComponents
                if let tagIdx = comps.firstIndex(of: "tag"), tagIdx + 1 < comps.count {
                    return comps[tagIdx + 1]
                }
            }
            return nil
        }()

        guard let tagName = discoveredTag, !tagName.isEmpty else {
            // No published release exists yet (GitHub stays at /releases)
            return nil
        }

        let latestVersion = normalizeVersion(tagName)
        guard isVersion(latestVersion, newerThan: currentVersion) else {
            // Already up to date — finish immediately without ever touching api.github.com!
            return nil
        }

        // 2. A newer version exists! Prefer rich API metadata if not rate-limited, otherwise fall back cleanly to web + Atom.
        if let apiRelease = try? await fetchReleaseFromAPI(tagName: tagName, currentVersion: currentVersion) {
            return apiRelease
        }

        return try await fetchReleaseFromWebFallback(tagName: tagName, version: latestVersion, currentVersion: currentVersion)
    }

    private nonisolated static func fetchReleaseFromAPI(tagName: String, currentVersion: String) async throws -> AppReleaseInfo? {
        let encodedTag = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tagName
        guard let apiURL = URL(string: releaseAPIBaseURL + encodedTag) else { return nil }
        var req = URLRequest(url: apiURL)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("YOMO/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        if payload.draft == true { return nil }

        let installerAsset = payload.assets.first(where: {
            $0.name.lowercased().hasSuffix(".dmg")
        }) ?? payload.assets.first(where: {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".zip") && !lower.contains("source")
        })

        guard let asset = installerAsset,
              let assetURL = URL(string: asset.browser_download_url),
              let htmlURL = URL(string: payload.html_url) else {
            return nil
        }

        let checksumsURL = payload.assets
            .first(where: { $0.name.uppercased().contains("SHA256") })
            .flatMap { URL(string: $0.browser_download_url) }

        let version = normalizeVersion(payload.tag_name)
        let iso = ISO8601DateFormatter()
        let publishedDate = payload.published_at.flatMap { iso.date(from: $0) }

        return AppReleaseInfo(
            tagName: payload.tag_name,
            version: version,
            title: (payload.name?.isEmpty == false ? payload.name! : payload.tag_name),
            notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            publishedAt: publishedDate,
            htmlURL: htmlURL,
            assetName: asset.name,
            assetDownloadURL: assetURL,
            assetSizeBytes: asset.size,
            checksumsURL: checksumsURL
        )
    }

    private nonisolated static func fetchReleaseFromWebFallback(
        tagName: String,
        version: String,
        currentVersion: String
    ) async throws -> AppReleaseInfo {
        let encodedTag = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tagName
        let htmlURL = URL(string: "https://github.com/\(githubRepo)/releases/tag/\(encodedTag)") ?? releasesPageURL
        let downloadBase = "https://github.com/\(githubRepo)/releases/download/\(encodedTag)/"

        // Discover exact DMG filename & SHA256SUMS.txt from the release's checksum manifest (zero API rate limit)
        var assetName = "YOMO-v\(version).dmg"
        var checksumsURL: URL? = nil
        if let candidateSumsURL = URL(string: downloadBase + "SHA256SUMS.txt") {
            var sumsReq = URLRequest(url: candidateSumsURL)
            sumsReq.timeoutInterval = 10
            sumsReq.setValue("YOMO/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            if let (sumsData, sumsResp) = try? await URLSession.shared.data(for: sumsReq),
               let http = sumsResp as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let sumsText = String(data: sumsData, encoding: .utf8) {
                checksumsURL = candidateSumsURL
                for rawLine in sumsText.components(separatedBy: .newlines) {
                    let parts = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(whereSeparator: { $0 == " " || $0 == "\t" })
                    if parts.count >= 2 {
                        let name = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*./"))
                        if name.lowercased().hasSuffix(".dmg") {
                            assetName = name
                            break
                        }
                    }
                }
            }
        }

        let encodedAsset = assetName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? assetName
        guard let assetURL = URL(string: downloadBase + encodedAsset) else {
            throw NSError(domain: "YOMOUpdate", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法构建新版本安装包下载地址"])
        }

        // Verify installer asset exists and read exact file size via lightweight HEAD request
        var headReq = URLRequest(url: assetURL)
        headReq.httpMethod = "HEAD"
        headReq.timeoutInterval = 12
        headReq.setValue("YOMO/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (_, headResp) = try await URLSession.shared.data(for: headReq)
        guard let headHTTP = headResp as? HTTPURLResponse, (200...299).contains(headHTTP.statusCode) else {
            throw NSError(domain: "YOMOUpdate", code: -2, userInfo: [NSLocalizedDescriptionKey: "最新版本未包含可用的 macOS 安装包（\(assetName)）"])
        }
        let sizeBytes = max(0, headHTTP.expectedContentLength)

        // Best-effort release notes from unrate-limited releases.atom feed
        let notes = (await fetchNotesFromAtomFeed(tagName: tagName, currentVersion: currentVersion)) ?? ""

        return AppReleaseInfo(
            tagName: tagName,
            version: version,
            title: "YOMO \(tagName)",
            notes: notes,
            publishedAt: nil,
            htmlURL: htmlURL,
            assetName: assetName,
            assetDownloadURL: assetURL,
            assetSizeBytes: sizeBytes,
            checksumsURL: checksumsURL
        )
    }

    private nonisolated static func fetchNotesFromAtomFeed(tagName: String, currentVersion: String) async -> String? {
        var req = URLRequest(url: releasesAtomURL)
        req.timeoutInterval = 8
        req.setValue("YOMO/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let xml = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Locate the <entry> block matching `/<tagName></id>` and extract plain-text release notes
        let entries = xml.components(separatedBy: "<entry>")
        for entry in entries.dropFirst() {
            guard entry.contains("/\(tagName)</id>") || entry.contains("/tag/\(tagName)\"") else { continue }
            guard let startRange = entry.range(of: "<content"),
                  let gtRange = entry.range(of: ">", range: startRange.upperBound..<entry.endIndex),
                  let endRange = entry.range(of: "</content>", range: gtRange.upperBound..<entry.endIndex) else {
                return nil
            }
            let raw = String(entry[gtRange.upperBound..<endRange.lowerBound])
            let unescaped = raw
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "</(p|li|h[1-6]|div)>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let cleaned = unescaped
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    public nonisolated static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        return s
    }

    public nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = parseSemVer(candidate)
        let rhs = parseSemVer(current)
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for i in 0..<count {
            let a = i < lhs.numbers.count ? lhs.numbers[i] : 0
            let b = i < rhs.numbers.count ? rhs.numbers[i] : 0
            if a != b { return a > b }
        }
        // Final release beats prerelease of same core version (e.g. 1.6.0 > 1.6.0-beta.1)
        if lhs.prerelease == nil && rhs.prerelease != nil { return true }
        if lhs.prerelease != nil && rhs.prerelease == nil { return false }
        if let lp = lhs.prerelease, let rp = rhs.prerelease {
            return lp.localizedStandardCompare(rp) == .orderedDescending
        }
        return false
    }

    private nonisolated static func parseSemVer(_ raw: String) -> (numbers: [Int], prerelease: String?) {
        let clean = normalizeVersion(raw)
        let parts = clean.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let nums = parts[0].split(separator: ".").map { Int($0) ?? 0 }
        let pre = parts.count > 1 ? String(parts[1]) : nil
        return (nums, pre)
    }

    private nonisolated static func verifyAndExtract(
        archiveURL: URL,
        stageRoot: URL,
        release: AppReleaseInfo,
        expectedBundleID: String
    ) -> Result<(appURL: URL, sha256Verified: Bool), Error> {
        // 1. Optional SHA-256 verification against Release SHA256SUMS.txt via Apple CryptoKit
        var sha256Verified = false
        if let checksumsURL = release.checksumsURL {
            do {
                let expectedHash = try fetchExpectedSHA256(from: checksumsURL, assetName: release.assetName)
                if let expectedHash {
                    let actualHash = try computeFileSHA256(at: archiveURL)
                    guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
                        return .failure(NSError(
                            domain: "YOMOUpdate",
                            code: -10,
                            userInfo: [NSLocalizedDescriptionKey: "安装包 SHA-256 校验未通过，已中止升级以保护安全"]
                        ))
                    }
                    sha256Verified = true
                }
            } catch {
                return .failure(NSError(
                    domain: "YOMOUpdate",
                    code: -11,
                    userInfo: [NSLocalizedDescriptionKey: "校验文件完整性失败：\(error.localizedDescription)"]
                ))
            }
        }

        let fm = FileManager.default
        let stagedAppURL = stageRoot.appendingPathComponent("YOMO.app", isDirectory: true)
        try? fm.removeItem(at: stagedAppURL)

        let ext = archiveURL.pathExtension.lowercased()
        if ext == "dmg" {
            let mountPoint = stageRoot.appendingPathComponent("mnt", isDirectory: true)
            do {
                try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            } catch {
                return .failure(error)
            }
            let attachCode = runProcess(
                "/usr/bin/hdiutil",
                ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mountPoint.path, archiveURL.path]
            )
            guard attachCode == 0 else {
                return .failure(NSError(domain: "YOMOUpdate", code: -12, userInfo: [NSLocalizedDescriptionKey: "挂载新版本 DMG 镜像失败"]))
            }
            defer {
                _ = runProcess("/usr/bin/hdiutil", ["detach", "-force", mountPoint.path])
            }

            guard let foundApp = findAppBundle(in: mountPoint) else {
                return .failure(NSError(domain: "YOMOUpdate", code: -13, userInfo: [NSLocalizedDescriptionKey: "DMG 镜像中未找到 YOMO.app"]))
            }
            do {
                try fm.copyItem(at: foundApp, to: stagedAppURL)
            } catch {
                return .failure(NSError(domain: "YOMOUpdate", code: -14, userInfo: [NSLocalizedDescriptionKey: "提取新版本应用失败：\(error.localizedDescription)"]))
            }
        } else if ext == "zip" {
            let extractDir = stageRoot.appendingPathComponent("extracted", isDirectory: true)
            do {
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
            } catch {
                return .failure(error)
            }
            let unzipCode = runProcess("/usr/bin/ditto", ["-xk", archiveURL.path, extractDir.path])
            guard unzipCode == 0, let foundApp = findAppBundle(in: extractDir) else {
                return .failure(NSError(domain: "YOMOUpdate", code: -15, userInfo: [NSLocalizedDescriptionKey: "解压新版本压缩包失败或未找到 YOMO.app"]))
            }
            do {
                try fm.moveItem(at: foundApp, to: stagedAppURL)
            } catch {
                return .failure(error)
            }
        } else {
            return .failure(NSError(domain: "YOMOUpdate", code: -16, userInfo: [NSLocalizedDescriptionKey: "不支持的安装包格式（.\(ext)）"]))
        }

        // 2. Validate extracted bundle ID & executable integrity
        let plistURL = stagedAppURL.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              bundleID == expectedBundleID else {
            return .failure(NSError(domain: "YOMOUpdate", code: -17, userInfo: [NSLocalizedDescriptionKey: "新版本应用包标识不匹配，已拒绝安装"]))
        }

        let execName = (plist["CFBundleExecutable"] as? String) ?? "YOMO"
        let execPath = stagedAppURL.appendingPathComponent("Contents/MacOS/\(execName)").path
        guard fm.isExecutableFile(atPath: execPath) else {
            return .failure(NSError(domain: "YOMOUpdate", code: -18, userInfo: [NSLocalizedDescriptionKey: "新版本应用包缺少可执行文件"]))
        }

        // 3. Remove downloaded archive to save temp space and clear quarantine on staged app for smooth relaunch
        try? fm.removeItem(at: archiveURL)
        _ = runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stagedAppURL.path])

        return .success((stagedAppURL, sha256Verified))
    }

    private nonisolated static func findAppBundle(in dir: URL) -> URL? {
        let fm = FileManager.default
        let direct = dir.appendingPathComponent("YOMO.app", isDirectory: true)
        if fm.fileExists(atPath: direct.path) {
            return direct
        }
        if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            if let app = items.first(where: { $0.pathExtension.lowercased() == "app" }) {
                return app
            }
            for sub in items {
                if let nested = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                   let app = nested.first(where: { $0.pathExtension.lowercased() == "app" }) {
                    return app
                }
            }
        }
        return nil
    }

    private nonisolated static func fetchExpectedSHA256(from url: URL, assetName: String) throws -> String? {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            let hash = String(parts[0])
            let file = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*./"))
            if file == assetName && hash.count == 64 && hash.allSatisfy(\.isHexDigit) {
                return hash
            }
        }
        return nil
    }

    private nonisolated static func computeFileSHA256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func buildSwapShellScript(
        oldPID: Int32,
        stagedAppPath: String,
        targetAppPath: String,
        stagingRootPath: String
    ) -> String {
        let qStaged = shellSingleQuoted(stagedAppPath)
        let qTarget = shellSingleQuoted(targetAppPath)
        let qBackup = shellSingleQuoted(targetAppPath + ".yomo-update-backup")
        let qStageRoot = shellSingleQuoted(stagingRootPath)
        return """
        #!/bin/sh
        OLD_PID=\(oldPID)
        i=0
        while kill -0 "$OLD_PID" 2>/dev/null && [ $i -lt 150 ]; do
            sleep 0.1
            i=$((i + 1))
        done
        STAGED=\(qStaged)
        TARGET=\(qTarget)
        BACKUP=\(qBackup)
        rm -rf "$BACKUP"
        if [ -e "$TARGET" ]; then
            mv "$TARGET" "$BACKUP" || exit 1
        fi
        if mv "$STAGED" "$TARGET"; then
            rm -rf "$BACKUP"
            /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
            /usr/bin/open "$TARGET"
        else
            if [ -e "$BACKUP" ]; then
                mv "$BACKUP" "$TARGET"
            fi
            /usr/bin/open "$TARGET"
            exit 1
        fi
        rm -rf \(qStageRoot)
        """
    }

    private func launchInPlaceSwapHelper(
        oldPID: Int32,
        stagedAppPath: String,
        targetAppPath: String,
        stagingRootPath: String
    ) -> Bool {
        let script = Self.buildSwapShellScript(
            oldPID: oldPID,
            stagedAppPath: stagedAppPath,
            targetAppPath: targetAppPath,
            stagingRootPath: stagingRootPath
        )
        let scriptURL = URL(fileURLWithPath: stagingRootPath).appendingPathComponent("apply-update.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = [scriptURL.path]
            proc.standardInput = FileHandle.nullDevice
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func launchPrivilegedSwapHelper(
        oldPID: Int32,
        stagedAppPath: String,
        targetAppPath: String,
        stagingRootPath: String
    ) -> Bool {
        let script = buildSwapShellScript(
            oldPID: oldPID,
            stagedAppPath: stagedAppPath,
            targetAppPath: targetAppPath,
            stagingRootPath: stagingRootPath
        )
        let scriptURL = URL(fileURLWithPath: stagingRootPath).appendingPathComponent("apply-update.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        } catch {
            return false
        }

        let cmd = "nohup /bin/sh \(shellSingleQuoted(scriptURL.path)) >/dev/null 2>&1 &"
        let escaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        return runProcess("/usr/bin/osascript", ["-e", appleScript]) == 0
    }

    private nonisolated static func shellSingleQuoted(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func runProcess(_ path: String, _ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardInput = FileHandle.nullDevice
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
}

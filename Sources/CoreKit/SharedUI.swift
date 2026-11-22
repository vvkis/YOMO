import Foundation
import AppKit
import SwiftUI

public enum GlassAppearanceMode: String, CaseIterable, Identifiable {
    case dark = "dark"
    case light = "light"
    case auto = "auto"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dark: return "深色烟熏"
        case .light: return "浅色亮玻璃"
        case .auto: return "跟随系统"
        }
    }
}

public enum OverviewTileID: String, CaseIterable, Identifiable, Codable, Sendable {
    case wifi = "wifi"
    case battery = "battery"
    case bluetoothAudio = "bluetoothAudio"
    case hidpi = "hidpi"
    case keepAwake = "keepAwake"
    case scrollReverser = "scrollReverser"
    case keyboardLock = "keyboardLock"
    case clipboard = "clipboard"
    case volume = "volume"
    case telemetry = "telemetry"

    public var id: String { rawValue }

    /// Default 4-column Bento Grid layout order matching the classic YOMO overview
    public static let defaultOrder: [OverviewTileID] = [
        .wifi, .battery,
        .bluetoothAudio, .hidpi, .keepAwake,
        .scrollReverser, .keyboardLock,
        .clipboard,
        .volume,
        .telemetry
    ]

    /// Default column span inside the 4-column Bento Grid (1 = 1/4 width, 2 = 1/2 width, 3 = 3/4 width, 4 = full width)
    public var defaultColSpan: Int {
        switch self {
        case .hidpi, .keepAwake, .keyboardLock:
            return 1
        case .wifi, .battery, .bluetoothAudio:
            return 2
        case .scrollReverser:
            return 3
        case .clipboard, .volume, .telemetry:
            return 4
        }
    }

    /// Supported column spans that the user can toggle between in layout editing mode
    public var supportedColSpans: [Int] {
        switch self {
        case .hidpi, .keepAwake, .keyboardLock:
            return [1, 2, 4]
        case .wifi, .battery, .bluetoothAudio:
            return [2, 4]
        case .scrollReverser:
            return [2, 3, 4]
        case .clipboard:
            return [2, 4]
        case .volume, .telemetry:
            return [4]
        }
    }

    public var canResizeSpan: Bool {
        supportedColSpans.count > 1
    }

    public var title: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .battery: return "电池"
        case .bluetoothAudio: return "蓝牙音频"
        case .hidpi: return "HiDPI"
        case .keepAwake: return "防休眠"
        case .scrollReverser: return "滚轮翻转"
        case .keyboardLock: return "键盘锁"
        case .clipboard: return "历史剪贴板"
        case .volume: return "声音输出"
        case .telemetry: return "系统占用"
        }
    }
}

/// Centralized module enable/disable toggles and overview Bento layout order shared across the Hub Console and Menu Bar shell.
public final class ModuleSettings: ObservableObject {
    private static let tileOrderStorageKey = "overview.tileOrder.v1"
    private static let tileSpansStorageKey = "overview.tileSpans.v1"

    @AppStorage("module.hidpi.enabled") public var hidpiEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("module.keepawake.enabled") public var keepAwakeEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("module.audiobluetooth.enabled") public var audioBluetoothEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("module.scrollreverser.enabled") public var scrollReverserEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("module.clipboard.enabled") public var clipboardEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("module.keyboardlock.enabled") public var keyboardLockEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("glass.appearance") public var glassAppearanceRaw: String = GlassAppearanceMode.dark.rawValue {
        willSet { objectWillChange.send() }
    }

    @Published public var overviewTileOrder: [OverviewTileID] {
        didSet {
            let rawList = overviewTileOrder.map(\.rawValue)
            UserDefaults.standard.set(rawList, forKey: Self.tileOrderStorageKey)
        }
    }

    @Published public var overviewTileSpans: [OverviewTileID: Int] {
        didSet {
            var rawDict: [String: Int] = [:]
            for (k, v) in overviewTileSpans {
                rawDict[k.rawValue] = v
            }
            UserDefaults.standard.set(rawDict, forKey: Self.tileSpansStorageKey)
        }
    }

    @Published public var isEditingOverviewLayout: Bool = false
    @Published public var draggingOverviewTile: OverviewTileID? = nil
    @Published public var dragTranslation: CGSize = .zero
    public var dragOriginFrame: CGRect = .zero
    public var lastDragEndTime: TimeInterval = 0
    public var lastSwapTarget: OverviewTileID? = nil
    public var lastSwapTime: TimeInterval = 0

    public var glassAppearance: GlassAppearanceMode {
        get { GlassAppearanceMode(rawValue: glassAppearanceRaw) ?? .dark }
        set {
            glassAppearanceRaw = newValue.rawValue
        }
    }

    public init() {
        let savedRaw = UserDefaults.standard.stringArray(forKey: Self.tileOrderStorageKey) ?? []
        self.overviewTileOrder = Self.normalizedTileOrder(from: savedRaw)

        let savedSpans = UserDefaults.standard.dictionary(forKey: Self.tileSpansStorageKey) as? [String: Int] ?? [:]
        self.overviewTileSpans = Self.normalizedTileSpans(from: savedSpans)
    }

    public func colSpan(for tile: OverviewTileID) -> Int {
        if let custom = overviewTileSpans[tile], tile.supportedColSpans.contains(custom) {
            return custom
        }
        return tile.defaultColSpan
    }

    public func setTileSpan(_ tile: OverviewTileID, span: Int) {
        guard tile.supportedColSpans.contains(span) else { return }
        overviewTileSpans[tile] = span
    }

    public func cycleTileSpan(_ tile: OverviewTileID) {
        let options = tile.supportedColSpans
        guard options.count > 1 else { return }
        let current = colSpan(for: tile)
        if let idx = options.firstIndex(of: current) {
            let next = options[(idx + 1) % options.count]
            overviewTileSpans[tile] = next
        } else {
            overviewTileSpans[tile] = tile.defaultColSpan
        }
    }

    public func isTileEnabled(_ tile: OverviewTileID) -> Bool {
        switch tile {
        case .wifi, .battery, .telemetry:
            return true
        case .bluetoothAudio, .volume:
            return audioBluetoothEnabled
        case .hidpi:
            return hidpiEnabled
        case .keepAwake:
            return keepAwakeEnabled
        case .scrollReverser:
            return scrollReverserEnabled
        case .keyboardLock:
            return keyboardLockEnabled
        case .clipboard:
            return clipboardEnabled
        }
    }

    public var enabledOverviewTiles: [OverviewTileID] {
        overviewTileOrder.filter { isTileEnabled($0) }
    }

    public var isDefaultOverviewOrder: Bool {
        guard overviewTileOrder == OverviewTileID.defaultOrder else { return false }
        for tile in OverviewTileID.allCases {
            if colSpan(for: tile) != tile.defaultColSpan {
                return false
            }
        }
        return true
    }

    public func moveOverviewTile(from source: OverviewTileID, to target: OverviewTileID, placeAfter: Bool? = nil) {
        guard source != target,
              let fromIdx = overviewTileOrder.firstIndex(of: source),
              let toIdx = overviewTileOrder.firstIndex(of: target) else {
            return
        }
        var updated = overviewTileOrder
        let item = updated.remove(at: fromIdx)
        if let placeAfter {
            if let newTargetIdx = updated.firstIndex(of: target) {
                let insertIdx = placeAfter ? min(updated.count, newTargetIdx + 1) : newTargetIdx
                updated.insert(item, at: insertIdx)
            } else {
                updated.insert(item, at: toIdx)
            }
        } else {
            updated.insert(item, at: toIdx)
        }
        overviewTileOrder = updated
    }

    /// Commits the packed visual order back into `overviewTileOrder` so array order always matches visual grid order.
    public func commitPackedVisualOrder(_ packedEnabledOrder: [OverviewTileID]) {
        var result: [OverviewTileID] = []
        var enabledIter = packedEnabledOrder.makeIterator()
        let enabledSet = Set(packedEnabledOrder)

        for item in overviewTileOrder {
            if enabledSet.contains(item) {
                if let next = enabledIter.next() {
                    result.append(next)
                }
            } else {
                result.append(item)
            }
        }
        while let remaining = enabledIter.next() {
            if !result.contains(remaining) {
                result.append(remaining)
            }
        }
        if result != overviewTileOrder {
            overviewTileOrder = result
        }
    }

    public func resetOverviewTileOrder() {
        overviewTileOrder = OverviewTileID.defaultOrder
        var defaults: [OverviewTileID: Int] = [:]
        for tile in OverviewTileID.allCases {
            defaults[tile] = tile.defaultColSpan
        }
        overviewTileSpans = defaults
    }

    private static func normalizedTileOrder(from rawStrings: [String]) -> [OverviewTileID] {
        var result: [OverviewTileID] = []
        var seen = Set<OverviewTileID>()
        for raw in rawStrings {
            if let id = OverviewTileID(rawValue: raw), seen.insert(id).inserted {
                result.append(id)
            }
        }
        for fallback in OverviewTileID.defaultOrder where seen.insert(fallback).inserted {
            result.append(fallback)
        }
        return result
    }

    private static func normalizedTileSpans(from rawDict: [String: Int]) -> [OverviewTileID: Int] {
        var result: [OverviewTileID: Int] = [:]
        for tile in OverviewTileID.allCases {
            if let saved = rawDict[tile.rawValue], tile.supportedColSpans.contains(saved) {
                result[tile] = saved
            } else {
                result[tile] = tile.defaultColSpan
            }
        }
        return result
    }
}

/// Reusable hover state tracker (avoids SwiftUIMacros `@State` requirement under CLT-only builds).
public final class HoverTracker: ObservableObject {
    @Published public var isHovering = false
    public init() {}
}

public struct HighlightRowStyle: ButtonStyle {
    @ObservedObject public var hover: HoverTracker
    public var cornerRadius: CGFloat

    public init(hover: HoverTracker, cornerRadius: CGFloat = 11) {
        self.hover = hover
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.primary.opacity(0.14)
                            : (hover.isHovering ? Color.primary.opacity(0.08) : Color.clear)
                    )
            )
            .onHover { hover.isHovering = $0 }
    }
}

/// Native macOS 26/27 Liquid Glass surface (NSGlassEffectView) with tuned tintColor for crisp foreground legibility.
public struct LiquidGlassPanelSurface: NSViewRepresentable {
    public let cornerRadius: CGFloat
    public let isDark: Bool

    public init(cornerRadius: CGFloat = 24, isDark: Bool) {
        self.cornerRadius = cornerRadius
        self.isDark = isDark
    }

    public func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.wantsLayer = true
            glass.layer?.masksToBounds = true
            glass.layer?.cornerRadius = cornerRadius
            glass.layer?.cornerCurve = .continuous
            applyTint(to: glass)
            return glass
        } else {
            let vfx = NSVisualEffectView(frame: .zero)
            vfx.blendingMode = .behindWindow
            vfx.state = .active
            vfx.wantsLayer = true
            vfx.layer?.masksToBounds = true
            vfx.layer?.cornerRadius = cornerRadius
            vfx.layer?.cornerCurve = .continuous
            applyFallback(to: vfx)
            return vfx
        }
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            glass.layer?.cornerRadius = cornerRadius
            applyTint(to: glass)
        } else if let vfx = nsView as? NSVisualEffectView {
            vfx.layer?.cornerRadius = cornerRadius
            applyFallback(to: vfx)
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    @available(macOS 26.0, *)
    private func applyTint(to glass: NSGlassEffectView) {
        if isDark {
            glass.tintColor = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 0.62)
        } else {
            glass.tintColor = NSColor(calibratedWhite: 0.97, alpha: 0.48)
        }
    }

    private func applyFallback(to vfx: NSVisualEffectView) {
        vfx.material = isDark ? .hudWindow : .popover
    }
}

/// Luminous elevation card modifier for Liquid Glass foreground tiles (avoids dark sunken smudges).
public struct GlassBentoStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        let isDark = (colorScheme == .dark)
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.115) : Color.white.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.24), Color.white.opacity(0.08)]
                                : [Color.white.opacity(0.96), Color.white.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: Color.black.opacity(isDark ? 0.24 : 0.08),
                radius: 4,
                y: isDark ? 2 : 1.5
            )
    }
}

extension View {
    public func glassBentoCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassBentoStyle(cornerRadius: cornerRadius))
    }
}

public struct GlassNeutralCircle<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let size: CGFloat
    private let content: Content

    public init(size: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                .frame(width: size, height: size)
            content
        }
    }
}

public struct SubpageHeader<Trailing: View>: View {
    public let title: String
    public let onBack: () -> Void
    private let trailing: Trailing

    public init(title: String, onBack: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 7) {
                    GlassNeutralCircle(size: 24) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            trailing
        }
    }
}

extension SubpageHeader where Trailing == EmptyView {
    public init(title: String, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack) {
            EmptyView()
        }
    }
}

public struct CircularProgressRing: View {
    public let progress: Double
    public let lineWidth: CGFloat
    public let color: Color
    public let trackOpacity: Double

    public init(progress: Double, lineWidth: CGFloat = 3.5, color: Color = .green, trackOpacity: Double = 0.14) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
        self.trackOpacity = trackOpacity
    }

    public var body: some View {
        let clamped = min(1.0, max(0.02, progress))
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

public struct TactileVolumeBar: View {
    @Environment(\.colorScheme) private var colorScheme
    public let volume: Float
    public let isMuted: Bool
    public let onVolumeChange: (Float) -> Void
    public let onToggleMute: () -> Void

    public init(
        volume: Float,
        isMuted: Bool,
        onVolumeChange: @escaping (Float) -> Void,
        onToggleMute: @escaping () -> Void
    ) {
        self.volume = volume
        self.isMuted = isMuted
        self.onVolumeChange = onVolumeChange
        self.onToggleMute = onToggleMute
    }

    public var body: some View {
        let isDark = (colorScheme == .dark)
        let displayVal = isMuted ? 0.0 : Double(min(1.0, max(0.0, volume)))

        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let fillW = displayVal > 0.01 ? max(30.0, w * CGFloat(displayVal)) : 0.0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.09))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isDark ? Color.white.opacity(0.16) : Color.white.opacity(0.65),
                                lineWidth: 0.7
                            )
                    )

                if fillW > 0 {
                    Capsule()
                        .fill(isDark ? Color.white.opacity(0.90) : Color.white.opacity(0.95))
                        .frame(width: fillW)
                        .shadow(color: Color.black.opacity(isDark ? 0 : 0.10), radius: 2, y: 1)
                }

                // Scrubber area (right of mute button or full track)
                Color.clear
                    .contentShape(Capsule())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let pct = min(1.0, max(0.0, Float(value.location.x / w)))
                                onVolumeChange(pct)
                            }
                    )

                // Left speaker mute button sits above scrubber for direct click
                Button(action: onToggleMute) {
                    Image(systemName: speakerIconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(fillW >= 28 ? Color.black.opacity(0.82) : Color.primary.opacity(0.78))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .clipShape(Capsule())
        }
        .frame(height: 30)
    }

    private var speakerIconName: String {
        if isMuted || volume <= 0.01 { return "speaker.slash.fill" }
        if volume < 0.35 { return "speaker.wave.1.fill" }
        if volume < 0.70 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

public enum Formatters {
    public static func splitSpeed(_ bytesPerSec: Double) -> (value: String, unit: String) {
        let kb = max(0, bytesPerSec) / 1024.0
        if kb < 999.5 {
            let num = kb >= 9.95 ? String(format: "%.0f", kb) : String(format: "%.1f", kb)
            return (num, "K")
        } else if kb < 999.5 * 1024.0 {
            let mb = kb / 1024.0
            let num = mb >= 9.95 ? String(format: "%.0f", mb) : String(format: "%.1f", mb)
            return (num, "M")
        } else {
            let gb = kb / (1024.0 * 1024.0)
            let num = gb >= 9.95 ? String(format: "%.0f", gb) : String(format: "%.1f", gb)
            return (num, "G")
        }
    }

    public static func compactSpeed(_ bytesPerSec: Double) -> String {
        let (val, unit) = splitSpeed(bytesPerSec)
        return "\(val)\(unit)"
    }
}

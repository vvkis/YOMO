import SwiftUI
import CoreKit
import DisplayHiDPIModule
import KeepAwakeModule
import AudioBluetoothModule
import ScrollReverserModule
import ClipboardModule
import KeyboardLockModule

private struct BentoRowBand {
    let minY: CGFloat
    let maxY: CGFloat
    let tiles: [OverviewTileID]
    let usedCols: Int
}

private struct BentoGridLayout {
    let frames: [OverviewTileID: CGRect]
    let spans: [OverviewTileID: Int]
    let rowBands: [BentoRowBand]
    let visualOrder: [OverviewTileID]
    let totalHeight: CGFloat
}

struct OverviewView: View {
    @ObservedObject var store: DuoBarStore
    @ObservedObject var prefs: AppPreferences
    @ObservedObject var moduleSettings: ModuleSettings
    @ObservedObject var displayStore: DisplayHiDPIStore
    @ObservedObject var keepAwakeStore: KeepAwakeStore
    @ObservedObject var audioBluetoothStore: AudioBluetoothStore
    @ObservedObject var scrollReverserStore: ScrollReverserStore
    @ObservedObject var clipboardStore: ClipboardStore
    @ObservedObject var keyboardLockStore: KeyboardLockStore
    let onNavigate: (PopoverPage) -> Void
    let onDismiss: () -> Void
    let onOpenConsole: (String?) -> Void
    let onQuit: () -> Void

    @StateObject private var wifiHover = HoverTracker()
    @StateObject private var audioHover = HoverTracker()
    @StateObject private var batHover = HoverTracker()
    @StateObject private var hidpiHover = HoverTracker()
    @StateObject private var awakeHover = HoverTracker()
    @StateObject private var scrollHover = HoverTracker()
    @StateObject private var keyLockHover = HoverTracker()
    @StateObject private var clipHover = HoverTracker()
    @StateObject private var telemetryHover = HoverTracker()

    private let gridTotalWidth: CGFloat = 290
    private let gridSpacing: CGFloat = 8

    /// Computes exact 4-column Bento Grid coordinates using First-Fit Row Packing:
    /// small tiles automatically fill available gaps in earlier partial rows (e.g. a 1x tile next to a 3x tile)
    /// instead of leaving dead empty holes when a 4x full-width tile is dragged between them.
    private var gridLayout: BentoGridLayout {
        let activeTiles = moduleSettings.enabledOverviewTiles
        let colUnit = (gridTotalWidth - gridSpacing * 3.0) / 4.0 // 66.5pt per column

        // 1. First-Fit Row Packing into 4-column rows
        var rows: [(items: [(tile: OverviewTileID, span: Int)], usedCols: Int)] = []

        for tile in activeTiles {
            let span = min(4, max(1, moduleSettings.colSpan(for: tile)))
            if let fitRowIdx = rows.firstIndex(where: { $0.usedCols + span <= 4 }) {
                rows[fitRowIdx].items.append((tile, span))
                rows[fitRowIdx].usedCols += span
            } else {
                rows.append((items: [(tile, span)], usedCols: span))
            }
        }

        // 2. Assign exact CGRect (x, y, width, height) for each tile and record row bands
        var frames: [OverviewTileID: CGRect] = [:]
        var spans: [OverviewTileID: Int] = [:]
        var rowBands: [BentoRowBand] = []
        var visualOrder: [OverviewTileID] = []
        var cursorY: CGFloat = 0

        for (rowIdx, row) in rows.enumerated() {
            let rowTiles = row.items.map(\.tile)
            let rowH = rowHeight(for: rowTiles)
            var cursorX: CGFloat = 0

            for item in row.items {
                let w = round(CGFloat(item.span) * colUnit + CGFloat(max(0, item.span - 1)) * gridSpacing)
                frames[item.tile] = CGRect(x: round(cursorX), y: round(cursorY), width: w, height: rowH)
                spans[item.tile] = item.span
                visualOrder.append(item.tile)
                cursorX += w + gridSpacing
            }

            rowBands.append(
                BentoRowBand(
                    minY: cursorY,
                    maxY: cursorY + rowH,
                    tiles: rowTiles,
                    usedCols: row.usedCols
                )
            )

            cursorY += rowH
            if rowIdx < rows.count - 1 {
                cursorY += gridSpacing
            }
        }

        return BentoGridLayout(
            frames: frames,
            spans: spans,
            rowBands: rowBands,
            visualOrder: visualOrder,
            totalHeight: max(50, cursorY)
        )
    }

    private func rowHeight(for tiles: [OverviewTileID]) -> CGFloat {
        if tiles.contains(.telemetry) { return 76 }
        if tiles.contains(.volume) { return 66 }
        if tiles.contains(.battery) { return 58 }
        if tiles.contains(.wifi) || tiles.contains(.bluetoothAudio) { return 54 }
        if tiles.contains(.scrollReverser) { return 50 }
        if tiles.contains(.clipboard) { return 48 }
        return 52
    }

    var body: some View {
        let isEditing = moduleSettings.isEditingOverviewLayout
        let activeTiles = moduleSettings.enabledOverviewTiles
        let layout = gridLayout

        VStack(spacing: 8) {
            // Edit-Layout Banner when user is rearranging or resizing tiles
            if isEditing {
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("拖拽移动 · 点角标 1×/2×/4× 缩放")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if !moduleSettings.isDefaultOverviewOrder {
                        Button {
                            withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                                moduleSettings.resetOverviewTileOrder()
                            }
                        } label: {
                            Text("恢复默认")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.86)) {
                            moduleSettings.isEditingOverviewLayout = false
                            moduleSettings.draggingOverviewTile = nil
                            moduleSettings.dragTranslation = .zero
                        }
                    } label: {
                        Text("完成")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8.5)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
            }

            // Flat Single-Layer ZStack Bento Canvas (Zero view destruction during cross-row reordering!)
            ZStack(alignment: .topLeading) {
                ForEach(activeTiles, id: \.self) { tile in
                    if let rect = layout.frames[tile] {
                        let span = layout.spans[tile] ?? tile.defaultColSpan
                        let isDraggingThis = (moduleSettings.draggingOverviewTile == tile)
                        let displayX = isDraggingThis
                            ? (moduleSettings.dragOriginFrame.minX + moduleSettings.dragTranslation.width)
                            : rect.minX
                        let displayY = isDraggingThis
                            ? (moduleSettings.dragOriginFrame.minY + moduleSettings.dragTranslation.height)
                            : rect.minY

                        tileView(for: tile, span: span, height: rect.height, isEditing: isEditing)
                            .frame(width: rect.width, height: rect.height)
                            .overlay(alignment: .topTrailing) {
                                if isEditing && tile.canResizeSpan {
                                    Button {
                                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
                                            moduleSettings.cycleTileSpan(tile)
                                        }
                                    } label: {
                                        HStack(spacing: 2) {
                                            Image(systemName: "arrow.left.and.right")
                                                .font(.system(size: 7.5, weight: .bold))
                                            Text("\(span)×")
                                                .font(.system(size: 9, weight: .bold))
                                                .monospacedDigit()
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor))
                                        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                    .help("点击切换组件宽度（\(tile.supportedColSpans.map { "\($0)×" }.joined(separator: " / "))）")
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius(for: tile), style: .continuous)
                                    .strokeBorder(
                                        isEditing ? Color.accentColor.opacity(isDraggingThis ? 0.95 : 0.42) : Color.clear,
                                        style: StrokeStyle(lineWidth: isEditing ? (isDraggingThis ? 1.6 : 1.1) : 0)
                                    )
                                    .allowsHitTesting(false)
                            )
                            .scaleEffect(isDraggingThis ? 1.03 : 1.0)
                            .shadow(
                                color: Color.black.opacity(isDraggingThis ? 0.35 : 0.0),
                                radius: isDraggingThis ? 10 : 0,
                                y: isDraggingThis ? 5 : 0
                            )
                            .zIndex(isDraggingThis ? 20 : 1)
                            .offset(x: displayX, y: displayY)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: isEditing ? 3 : 7, coordinateSpace: .named("BentoCanvas"))
                                    .onChanged { value in
                                        // In normal overview mode, allow direct drag-to-reorder on all tiles except volume slider;
                                        // resizing is strictly restricted to the dedicated layout-editing mode.
                                        guard isEditing || tile != .volume else { return }
                                        if moduleSettings.draggingOverviewTile != tile {
                                            moduleSettings.commitPackedVisualOrder(layout.visualOrder)
                                            moduleSettings.draggingOverviewTile = tile
                                            moduleSettings.dragOriginFrame = rect
                                        }
                                        moduleSettings.dragTranslation = value.translation

                                        let currentCenter = CGPoint(
                                            x: moduleSettings.dragOriginFrame.midX + value.translation.width,
                                            y: moduleSettings.dragOriginFrame.midY + value.translation.height
                                        )
                                        if let drop = findTargetDrop(at: currentCenter, excluding: tile, in: layout) {
                                            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.82)) {
                                                moduleSettings.moveOverviewTile(
                                                    from: tile,
                                                    to: drop.target,
                                                    placeAfter: drop.placeAfter
                                                )
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        guard moduleSettings.draggingOverviewTile == tile else { return }
                                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
                                            moduleSettings.commitPackedVisualOrder(gridLayout.visualOrder)
                                            moduleSettings.draggingOverviewTile = nil
                                            moduleSettings.dragTranslation = .zero
                                        }
                                    },
                                including: isEditing ? .all : (tile == .volume ? .none : .all)
                            )
                            .contextMenu {
                                Button(isEditing ? "完成排版" : "进入排版页面（调整组件大小）") {
                                    withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                                        moduleSettings.isEditingOverviewLayout.toggle()
                                        if !moduleSettings.isEditingOverviewLayout {
                                            moduleSettings.draggingOverviewTile = nil
                                            moduleSettings.dragTranslation = .zero
                                        }
                                    }
                                }
                                if isEditing && tile.canResizeSpan {
                                    Divider()
                                    ForEach(tile.supportedColSpans, id: \.self) { optSpan in
                                        Button("\(spanLabel(optSpan))\(span == optSpan ? " ✓" : "")") {
                                            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
                                                moduleSettings.setTileSpan(tile, span: optSpan)
                                            }
                                        }
                                    }
                                }
                                if !moduleSettings.isDefaultOverviewOrder {
                                    Divider()
                                    Button("恢复默认排版与尺寸") {
                                        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                                            moduleSettings.resetOverviewTileOrder()
                                        }
                                    }
                                }
                            }
                    }
                }
            }
            .coordinateSpace(name: "BentoCanvas")
            .frame(width: gridTotalWidth, height: layout.totalHeight, alignment: .topLeading)

            // Integrated Utility Footer
            HStack {
                Button {
                    onOpenConsole(nil)
                } label: {
                    Label("控制台", systemImage: "square.grid.2x2")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.9))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                        moduleSettings.isEditingOverviewLayout.toggle()
                        if !moduleSettings.isEditingOverviewLayout {
                            moduleSettings.draggingOverviewTile = nil
                            moduleSettings.dragTranslation = .zero
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "square.grid.3x2")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(isEditing ? "完成排版" : "排版")
                            .font(.system(size: 11.5, weight: isEditing ? .semibold : .regular))
                    }
                    .foregroundStyle(isEditing ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("开启后可直接按住卡片丝滑拖拽换位，或点击卡片右上角 1×/2×/4× 放大缩小")

                Spacer()

                Button {
                    onNavigate(.settings)
                } label: {
                    Text("外观与样式")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onQuit) {
                    Text("退出")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.top, 1)
        }
        .padding(13)
    }

    private func findTargetDrop(
        at point: CGPoint,
        excluding dragged: OverviewTileID,
        in layout: BentoGridLayout
    ) -> (target: OverviewTileID, placeAfter: Bool?)? {
        // 1. Direct hit on an existing tile's core region
        for (tile, rect) in layout.frames where tile != dragged {
            let hitBox = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
            if hitBox.contains(point) {
                return (target: tile, placeAfter: nil)
            }
        }

        // 2. Empty right-hand slot on a partial row (e.g. dragging 1x Keyboard Lock into the empty 1-col gap next to 3x Scroll Reverser)
        for band in layout.rowBands {
            if point.y >= band.minY && point.y <= band.maxY {
                let rowOtherTiles = band.tiles.filter { $0 != dragged }
                guard let lastTile = rowOtherTiles.last,
                      let lastRect = layout.frames[lastTile] else {
                    continue
                }
                if point.x > lastRect.midX {
                    return (target: lastTile, placeAfter: true)
                } else if let firstTile = rowOtherTiles.first,
                          let firstRect = layout.frames[firstTile],
                          point.x < firstRect.midX {
                    return (target: firstTile, placeAfter: false)
                }
            }
        }
        return nil
    }

    private func spanLabel(_ span: Int) -> String {
        switch span {
        case 1: return "小尺寸 (1× · 1/4 宽)"
        case 2: return "中尺寸 (2× · 半行宽)"
        case 3: return "宽尺寸 (3× · 3/4 宽)"
        default: return "大尺寸 (4× · 整行宽)"
        }
    }

    private func cornerRadius(for tile: OverviewTileID) -> CGFloat {
        switch tile {
        case .hidpi, .keepAwake, .keyboardLock:
            return 14
        case .scrollReverser, .clipboard:
            return 15
        default:
            return 16
        }
    }

    private func canTriggerTileTap(isEditing: Bool) -> Bool {
        !isEditing && moduleSettings.draggingOverviewTile == nil
    }

    // MARK: - Individual Bento Tile Builders (Adapt gracefully to 1x / 2x / 3x / 4x spans)

    @ViewBuilder
    private func tileView(for tile: OverviewTileID, span: Int, height: CGFloat, isEditing: Bool) -> some View {
        switch tile {
        case .wifi:
            wifiTile(span: span, height: height, isEditing: isEditing)
        case .bluetoothAudio:
            bluetoothAudioTile(span: span, height: height, isEditing: isEditing)
        case .battery:
            batteryTile(span: span, height: height, isEditing: isEditing)
        case .hidpi:
            hidpiTile(span: span, height: height, isEditing: isEditing)
        case .keepAwake:
            keepAwakeTile(span: span, height: height, isEditing: isEditing)
        case .scrollReverser:
            scrollReverserTile(span: span, height: height, isEditing: isEditing)
        case .keyboardLock:
            keyboardLockTile(span: span, height: height, isEditing: isEditing)
        case .clipboard:
            clipboardTile(span: span, height: height, isEditing: isEditing)
        case .volume:
            volumeTile(height: height, isEditing: isEditing)
        case .telemetry:
            telemetryTile(height: height, isEditing: isEditing)
        }
    }

    private func wifiTile(span: Int, height: CGFloat, isEditing: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                if !isEditing {
                    store.setWiFiPower(!store.wifi.isPoweredOn)
                }
            } label: {
                ZStack {
                    if store.wifi.isPoweredOn {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 28, height: 28)
                    } else {
                        GlassNeutralCircle(size: 28) { EmptyView() }
                    }
                    Image(systemName: store.wifi.isPoweredOn ? "wifi" : "wifi.slash")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(store.wifi.isPoweredOn ? Color.white : Color.primary)
                }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!isEditing)
            .help(store.wifi.isPoweredOn ? "关闭 Wi-Fi" : "开启 Wi-Fi")

            VStack(alignment: .leading, spacing: 1.5) {
                Text("Wi-Fi")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(compactWifiLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if span >= 4, let band = store.wifi.channelBandLabel, store.wifi.isConnected {
                Text(band)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 16)
        .opacity(wifiHover.isHovering && !isEditing ? 0.92 : 1.0)
        .contentShape(Rectangle())
        .onHover { wifiHover.isHovering = $0 }
        .onTapGesture {
            if canTriggerTileTap(isEditing: isEditing) {
                onNavigate(.wifi)
            }
        }
    }

    private func bluetoothAudioTile(span: Int, height: CGFloat, isEditing: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                if audioBluetoothStore.connectedAudioBluetooth != nil {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 28)
                } else {
                    GlassNeutralCircle(size: 28) { EmptyView() }
                }
                Image(systemName: audioBluetoothStore.connectedAudioBluetooth?.symbolName ?? "airpodspro")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(audioBluetoothStore.connectedAudioBluetooth != nil ? Color.white : Color.primary)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(audioBluetoothStore.connectedAudioBluetooth?.name ?? "蓝牙音频")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(compactAudioLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 16)
        .opacity(audioHover.isHovering && !isEditing ? 0.92 : 1.0)
        .contentShape(Rectangle())
        .onHover { audioHover.isHovering = $0 }
        .onTapGesture {
            if canTriggerTileTap(isEditing: isEditing) {
                onNavigate(.audioBluetooth)
            }
        }
    }

    private func batteryTile(span: Int, height: CGFloat, isEditing: Bool) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text("电池")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.68))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.45))
                }
                Text("\(store.battery.percentage)%")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(compactBatterySub)
                    .font(.system(size: 10.5))
                    .foregroundStyle(store.battery.isLowPowerMode ? Color.orange : Color.primary.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if span >= 4 {
                Text(store.battery.powerSourceLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 6)
            }

            ZStack {
                CircularProgressRing(
                    progress: Double(store.battery.percentage) / 100.0,
                    lineWidth: 3.8,
                    color: store.battery.ringColor
                )
                .frame(width: 35, height: 35)

                if store.battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                } else if store.battery.isLowPowerMode {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 16)
        .opacity(batHover.isHovering && !isEditing ? 0.92 : 1.0)
        .contentShape(Rectangle())
        .onHover { batHover.isHovering = $0 }
        .onTapGesture {
            if canTriggerTileTap(isEditing: isEditing) {
                onNavigate(.battery)
            }
        }
    }

    private func hidpiTile(span: Int, height: CGFloat, isEditing: Bool) -> some View {
        Group {
            if span == 1 {
                VStack(spacing: 3) {
                    Image(systemName: "display")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("HiDPI")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 8) {
                    GlassNeutralCircle(size: 28) {
                        Image(systemName: "display")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("显示器 / HiDPI")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(displayStore.primarySummary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 14)
        .opacity(hidpiHover.isHovering && !isEditing ? 0.9 : 1.0)
        .contentShape(Rectangle())
        .onHover { hidpiHover.isHovering = $0 }
        .onTapGesture {
            if canTriggerTileTap(isEditing: isEditing) {
                onNavigate(.display)
            }
        }
    }

    private func keepAwakeTile(span: Int, height: CGFloat, isEditing: Bool) -> some View {
        Group {
            if span == 1 {
                VStack(spacing: 3) {
                    Image(systemName: keepAwakeStore.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(keepAwakeStore.isActive ? Color.orange : Color.primary)
                    Text(keepAwakeStore.isActive ? "常亮中" : "防休眠")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(keepAwakeStore.isActive ? Color.orange : Color.primary)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 8) {
                    ZStack {
                        if keepAwakeStore.isActive {
                            Circle().fill(Color.orange).frame(width: 28, height: 28)
                        } else {
                            GlassNeutralCircle(size: 28) { EmptyView() }
                        }
                        Image(systemName: keepAwakeStore.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(keepAwakeStore.isActive ? Color.white : Color.primary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("防休眠")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(keepAwakeStore.statusSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(keepAwakeStore.isActive ? Color.orange : Color.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 14)
        .opacity(awakeHover.isHovering && !isEditing ? 0.9 : 1.0)
        .contentShape(Rectangle())
        .onHover { awakeHover.isHovering = $0 }
        .onTapGesture {
            if canTriggerTileTap(isEditing: isEditing) {
                onNavigate(.keepAwake)
            }
        }
    }

    private func scrollReverserTile(span: Int, height: CGFloat, isEditing: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    if scrollReverserStore.isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 28, height: 28)
                    } else {
                        GlassNeutralCircle(size: 28) { EmptyView() }
                    }
                    Image(systemName: scrollReverserStore.isActive ? "computermouse.fill" : "computermouse")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(scrollReverserStore.isActive ? Color.white : Color.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("滚轮翻转")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(scrollReverserStore.statusSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(scrollReverserStore.isActive ? Color.accentColor : Color.primary.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                if span >= 3 {
                    Toggle("", isOn: Binding(
                        get: { scrollReverserStore.isActive },
                        set: { scrollReverserStore.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .allowsHitTesting(false)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if canTriggerTileTap(isEditing: isEditing) {
                    scrollReverserStore.toggle()
                }
            }
            .help(scrollReverserStore.isActive ? "关闭滚轮翻转" : "开启滚轮翻转")

            Divider()
                .frame(height: 20)
                .opacity(0.45)

            Button {
                if !isEditing {
                    onNavigate(.scrollReverser)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HighlightRowStyle(hover: scrollHover, cornerRadius: 10))
            .allowsHitTesting(!isEditing)
            .padding(.horizontal, 3)
            .help("滚轮翻转详细设置")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 15)
    }

    private func keyboardLockTile(span: Int, height: CGFloat, isEditing: Bool) -> some View {
        Group {
            if span == 1 {
                VStack(spacing: 3) {
                    Image(systemName: keyboardLockStore.isLocked ? "lock.fill" : "keyboard")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(keyboardLockStore.isLocked ? Color.orange : Color.primary)
                    Text(keyboardLockStore.isLocked ? "已锁定" : "键盘锁")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(keyboardLockStore.isLocked ? Color.orange : Color.primary)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 8) {
                    ZStack {
                        if keyboardLockStore.isLocked {
                            Circle().fill(Color.orange).frame(width: 28, height: 28)
                        } else {
                            GlassNeutralCircle(size: 28) { EmptyView() }
                        }
                        Image(systemName: keyboardLockStore.isLocked ? "lock.fill" : "keyboard")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(keyboardLockStore.isLocked ? Color.white : Color.primary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("键盘锁")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(keyboardLockStore.isLocked ? "键盘已锁定 (⌃⌥⌘U 解锁)" : "一键锁定键盘清洁擦拭")
                            .font(.system(size: 10))
                            .foregroundStyle(keyboardLockStore.isLocked ? Color.orange : Color.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 14)
        .opacity(keyLockHover.isHovering && !isEditing ? 0.9 : 1.0)
        .contentShape(Rectangle())
        .onHover { keyLockHover.isHovering = $0 }
        .onTapGesture {
            guard canTriggerTileTap(isEditing: isEditing) else { return }
            if keyboardLockStore.isLocked {
                keyboardLockStore.unlock()
            } else if keyboardLockStore.lock() {
                onDismiss()
            } else {
                onOpenConsole("keyboardLock")
            }
        }
        .help(keyboardLockStore.isLocked ? "点击解锁键盘（或按 ⌃⌥⌘U）" : "清理键盘时一键锁定键盘输入")
    }

    private func clipboardTile(span: Int, height: CGFloat, isEditing: Bool) -> some View {
        HStack(spacing: 9) {
            GlassNeutralCircle(size: 28) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("历史剪贴板")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if span >= 4 && clipboardStore.globalHotkeyEnabled {
                        Text("⇧⌘V")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Text(clipboardStore.latestPreviewSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary.opacity(0.68))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if clipboardStore.totalCount > 0 {
                Text("\(clipboardStore.totalCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 15)
        .opacity(clipHover.isHovering && !isEditing ? 0.92 : 1.0)
        .contentShape(Rectangle())
        .onHover { clipHover.isHovering = $0 }
        .onTapGesture {
            if canTriggerTileTap(isEditing: isEditing) {
                onNavigate(.clipboard)
            }
        }
    }

    private func volumeTile(height: CGFloat, isEditing: Bool) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("声音输出 · \(audioBluetoothStore.currentOutputName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(round((audioBluetoothStore.isMuted ? 0 : audioBluetoothStore.outputVolume) * 100)))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .monospacedDigit()
            }
            .padding(.horizontal, 2)

            TactileVolumeBar(
                volume: audioBluetoothStore.outputVolume,
                isMuted: audioBluetoothStore.isMuted,
                onVolumeChange: { audioBluetoothStore.setOutputVolume($0) },
                onToggleMute: { audioBluetoothStore.setOutputMute(!audioBluetoothStore.isMuted) }
            )
            .allowsHitTesting(!isEditing)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 16)
    }

    private func telemetryTile(height: CGFloat, isEditing: Bool) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                TelemetryStatCell(
                    label: "CPU",
                    value: String(format: "%.0f%%", store.cpu.totalUsage),
                    tint: store.cpu.totalUsage >= 80 ? .red : .primary
                )
                Divider().frame(height: 22).opacity(0.45)
                TelemetryStatCell(
                    label: "内存",
                    value: String(format: "%.0f%%", store.memory.usagePercent),
                    tint: memoryTextColor
                )
                Divider().frame(height: 22).opacity(0.45)
                TelemetryStatCell(
                    label: "磁盘",
                    value: String(format: "%.0f%%", store.disk.usagePercent),
                    tint: store.disk.usagePercent >= 88 ? .red : .primary
                )
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.45))
                    .padding(.top, 2)
                    .padding(.trailing, 2)
            }

            Divider().opacity(0.45)

            HStack {
                Text(store.network.localIP == "--" ? "离线" : store.network.localIP)
                    .foregroundStyle(.primary.opacity(0.72))
                Spacer()
                Text("↑ \(Formatters.compactSpeed(store.network.uploadBytesPerSec)) · ↓ \(Formatters.compactSpeed(store.network.downloadBytesPerSec))")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary.opacity(0.88))
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 16)
        .opacity(telemetryHover.isHovering && !isEditing ? 0.92 : 1.0)
        .contentShape(Rectangle())
        .onHover { telemetryHover.isHovering = $0 }
        .onTapGesture {
            if canTriggerTileTap(isEditing: isEditing) {
                onNavigate(.telemetry)
            }
        }
    }

    // MARK: - Computed Labels

    private var compactWifiLabel: String {
        if !store.wifi.isPoweredOn { return "已关闭" }
        if !store.wifi.isConnected { return "未连接" }
        return store.wifi.currentSSID ?? "已连接"
    }

    private var compactAudioLabel: String {
        if let bt = audioBluetoothStore.connectedAudioBluetooth {
            if let l = bt.leftBattery, let r = bt.rightBattery {
                return "L\(l) R\(r)"
            }
            if let m = bt.mainBattery {
                return "\(m)%"
            }
            return "已连接"
        }
        return audioBluetoothStore.currentOutputName
    }

    private var compactBatterySub: String {
        if store.battery.isLowPowerMode { return "低电量模式" }
        if store.battery.isCharging { return "充电中" }
        if store.battery.isPluggedIn { return "电源供电" }
        return store.battery.timeRemainingText.replacingOccurrences(of: "剩余约 ", with: "")
    }

    private var memoryTextColor: Color {
        switch store.memory.pressureLevel {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return .primary
        }
    }
}

private struct TelemetryStatCell: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.65))
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

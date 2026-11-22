import SwiftUI
import UniformTypeIdentifiers
import CoreKit
import DisplayHiDPIModule
import KeepAwakeModule
import AudioBluetoothModule
import ScrollReverserModule
import ClipboardModule
import KeyboardLockModule

private struct BentoRow: Identifiable {
    let id: String
    let tiles: [OverviewTileID]

    var totalColSpan: Int {
        tiles.reduce(0) { $0 + $1.colSpan }
    }

    var rowHeight: CGFloat {
        if tiles.contains(.telemetry) { return 76 }
        if tiles.contains(.volume) { return 66 }
        if tiles.contains(.battery) { return 58 }
        if tiles.contains(.wifi) || tiles.contains(.bluetoothAudio) { return 54 }
        if tiles.contains(.scrollReverser) { return 50 }
        if tiles.contains(.clipboard) { return 48 }
        return 52
    }
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

    /// Packs the user-ordered tiles into 4-column Bento rows.
    private var packedRows: [BentoRow] {
        let activeTiles = moduleSettings.enabledOverviewTiles
        var rows: [BentoRow] = []
        var currentTiles: [OverviewTileID] = []
        var currentCols = 0

        for tile in activeTiles {
            let span = tile.colSpan
            if currentCols + span > 4 && !currentTiles.isEmpty {
                rows.append(BentoRow(id: currentTiles.map(\.rawValue).joined(separator: "-"), tiles: currentTiles))
                currentTiles = [tile]
                currentCols = span
            } else {
                currentTiles.append(tile)
                currentCols += span
                if currentCols == 4 {
                    rows.append(BentoRow(id: currentTiles.map(\.rawValue).joined(separator: "-"), tiles: currentTiles))
                    currentTiles = []
                    currentCols = 0
                }
            }
        }
        if !currentTiles.isEmpty {
            rows.append(BentoRow(id: currentTiles.map(\.rawValue).joined(separator: "-"), tiles: currentTiles))
        }
        return rows
    }

    /// Computes exact fixed pixel width for each tile in a 4-column row so every row fills 290pt cleanly.
    private func tileWidth(for tile: OverviewTileID, in row: BentoRow) -> CGFloat {
        let count = row.tiles.count
        let totalGaps = CGFloat(max(0, count - 1)) * gridSpacing
        let availableWidth = gridTotalWidth - totalGaps
        let rowSpanSum = max(1, row.totalColSpan)
        return floor((availableWidth * CGFloat(tile.colSpan)) / CGFloat(rowSpanSum))
    }

    var body: some View {
        let isEditing = moduleSettings.isEditingOverviewLayout

        VStack(spacing: 8) {
            // Optional Edit-Layout Banner when user is rearranging tiles
            if isEditing {
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("按住卡片拖拽调整位置")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.88))

                    Spacer(minLength: 4)

                    if !moduleSettings.isDefaultOverviewOrder {
                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                moduleSettings.resetOverviewTileOrder()
                            }
                        } label: {
                            Text("恢复默认")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                            moduleSettings.isEditingOverviewLayout = false
                            moduleSettings.draggingOverviewTile = nil
                        }
                    } label: {
                        Text("完成")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
            }

            // Dynamic 4-Column Drag-and-Drop Bento Grid
            ForEach(packedRows) { row in
                HStack(spacing: gridSpacing) {
                    ForEach(row.tiles) { tile in
                        let w = tileWidth(for: tile, in: row)
                        let isDraggingThis = (moduleSettings.draggingOverviewTile == tile)

                        tileView(for: tile, height: row.rowHeight, isEditing: isEditing)
                            .frame(width: w, height: row.rowHeight)
                            .overlay(alignment: .topTrailing) {
                                if isEditing {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .padding(4.5)
                                        .background(Circle().fill(Color.primary.opacity(0.10)))
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius(for: tile), style: .continuous)
                                    .strokeBorder(
                                        isEditing ? Color.accentColor.opacity(isDraggingThis ? 0.85 : 0.38) : Color.clear,
                                        style: StrokeStyle(lineWidth: isEditing ? 1.2 : 0, dash: isDraggingThis ? [4, 3] : [])
                                    )
                                    .allowsHitTesting(false)
                            )
                            .scaleEffect(isDraggingThis ? 0.96 : 1.0)
                            .opacity(isDraggingThis ? 0.65 : 1.0)
                            .contentShape(RoundedRectangle(cornerRadius: cornerRadius(for: tile), style: .continuous))
                            .onDrag {
                                moduleSettings.draggingOverviewTile = tile
                                return NSItemProvider(object: tile.rawValue as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: OverviewTileDropDelegate(
                                    targetTile: tile,
                                    moduleSettings: moduleSettings
                                )
                            )
                            .contextMenu {
                                Button(isEditing ? "完成排版" : "自定义拖拽排版") {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                        moduleSettings.isEditingOverviewLayout.toggle()
                                        if !moduleSettings.isEditingOverviewLayout {
                                            moduleSettings.draggingOverviewTile = nil
                                        }
                                    }
                                }
                                if !moduleSettings.isDefaultOverviewOrder {
                                    Button("恢复默认排版") {
                                        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                            moduleSettings.resetOverviewTileOrder()
                                        }
                                    }
                                }
                            }
                    }
                }
                .frame(width: gridTotalWidth, alignment: .leading)
            }

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
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        moduleSettings.isEditingOverviewLayout.toggle()
                        if !moduleSettings.isEditingOverviewLayout {
                            moduleSettings.draggingOverviewTile = nil
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
                .help("按住任意组件卡片拖拽即可自由调整总览布局")

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
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: moduleSettings.overviewTileOrder)
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

    // MARK: - Individual Bento Tile Builders

    @ViewBuilder
    private func tileView(for tile: OverviewTileID, height: CGFloat, isEditing: Bool) -> some View {
        switch tile {
        case .wifi:
            wifiTile(height: height, isEditing: isEditing)
        case .bluetoothAudio:
            bluetoothAudioTile(height: height, isEditing: isEditing)
        case .battery:
            batteryTile(height: height, isEditing: isEditing)
        case .hidpi:
            hidpiTile(height: height, isEditing: isEditing)
        case .keepAwake:
            keepAwakeTile(height: height, isEditing: isEditing)
        case .scrollReverser:
            scrollReverserTile(height: height, isEditing: isEditing)
        case .keyboardLock:
            keyboardLockTile(height: height, isEditing: isEditing)
        case .clipboard:
            clipboardTile(height: height, isEditing: isEditing)
        case .volume:
            volumeTile(height: height, isEditing: isEditing)
        case .telemetry:
            telemetryTile(height: height, isEditing: isEditing)
        }
    }

    private func wifiTile(height: CGFloat, isEditing: Bool) -> some View {
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
            if !isEditing {
                onNavigate(.wifi)
            }
        }
    }

    private func bluetoothAudioTile(height: CGFloat, isEditing: Bool) -> some View {
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
            if !isEditing {
                onNavigate(.audioBluetooth)
            }
        }
    }

    private func batteryTile(height: CGFloat, isEditing: Bool) -> some View {
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
            if !isEditing {
                onNavigate(.battery)
            }
        }
    }

    private func hidpiTile(height: CGFloat, isEditing: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: "display")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("HiDPI")
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 14)
        .opacity(hidpiHover.isHovering && !isEditing ? 0.9 : 1.0)
        .contentShape(Rectangle())
        .onHover { hidpiHover.isHovering = $0 }
        .onTapGesture {
            if !isEditing {
                onNavigate(.display)
            }
        }
    }

    private func keepAwakeTile(height: CGFloat, isEditing: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: keepAwakeStore.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(keepAwakeStore.isActive ? Color.orange : Color.primary)
            Text(keepAwakeStore.isActive ? "常亮中" : "防休眠")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(keepAwakeStore.isActive ? Color.orange : Color.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 14)
        .opacity(awakeHover.isHovering && !isEditing ? 0.9 : 1.0)
        .contentShape(Rectangle())
        .onHover { awakeHover.isHovering = $0 }
        .onTapGesture {
            if !isEditing {
                onNavigate(.keepAwake)
            }
        }
    }

    private func scrollReverserTile(height: CGFloat, isEditing: Bool) -> some View {
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

                Toggle("", isOn: Binding(
                    get: { scrollReverserStore.isActive },
                    set: { scrollReverserStore.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .allowsHitTesting(false)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isEditing {
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
                    .frame(width: 26, height: 36)
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

    private func keyboardLockTile(height: CGFloat, isEditing: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: keyboardLockStore.isLocked ? "lock.fill" : "keyboard")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(keyboardLockStore.isLocked ? Color.orange : Color.primary)
            Text(keyboardLockStore.isLocked ? "已锁定" : "键盘锁")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(keyboardLockStore.isLocked ? Color.orange : Color.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBentoCard(cornerRadius: 14)
        .opacity(keyLockHover.isHovering && !isEditing ? 0.9 : 1.0)
        .contentShape(Rectangle())
        .onHover { keyLockHover.isHovering = $0 }
        .onTapGesture {
            guard !isEditing else { return }
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

    private func clipboardTile(height: CGFloat, isEditing: Bool) -> some View {
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
                    if clipboardStore.globalHotkeyEnabled {
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
            if !isEditing {
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
            if !isEditing {
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

private struct OverviewTileDropDelegate: DropDelegate {
    let targetTile: OverviewTileID
    let moduleSettings: ModuleSettings

    func dropEntered(info: DropInfo) {
        guard let source = moduleSettings.draggingOverviewTile,
              source != targetTile else {
            return
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            moduleSettings.moveOverviewTile(from: source, to: targetTile)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        moduleSettings.draggingOverviewTile = nil
        return true
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

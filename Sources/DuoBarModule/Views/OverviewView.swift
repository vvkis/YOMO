import SwiftUI
import CoreKit
import DisplayHiDPIModule
import KeepAwakeModule
import AudioBluetoothModule

struct OverviewView: View {
    @ObservedObject var store: DuoBarStore
    @ObservedObject var prefs: AppPreferences
    @ObservedObject var moduleSettings: ModuleSettings
    @ObservedObject var displayStore: DisplayHiDPIStore
    @ObservedObject var keepAwakeStore: KeepAwakeStore
    @ObservedObject var audioBluetoothStore: AudioBluetoothStore
    let onNavigate: (PopoverPage) -> Void
    let onOpenConsole: () -> Void
    let onQuit: () -> Void

    @StateObject private var batHover = HoverTracker()
    @StateObject private var hidpiHover = HoverTracker()
    @StateObject private var awakeHover = HoverTracker()
    @StateObject private var telemetryHover = HoverTracker()

    var body: some View {
        VStack(spacing: 9) {
            // 1. Asymmetric 2-Column Bento Top Section
            HStack(spacing: 8) {
                // Left Column: Symmetrical 50/50 Connectivity Stack (Wi-Fi + AirPods/Audio)
                VStack(spacing: 0) {
                    // Top Half: Wi-Fi
                    HStack(spacing: 8) {
                        Button {
                            store.setWiFiPower(!store.wifi.isPoweredOn)
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
                        .help(store.wifi.isPoweredOn ? "关闭 Wi-Fi" : "开启 Wi-Fi")

                        VStack(alignment: .leading, spacing: 1.5) {
                            Text("Wi-Fi")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(compactWifiLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary.opacity(0.72))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onNavigate(.wifi)
                    }

                    if moduleSettings.audioBluetoothEnabled {
                        Divider()
                            .padding(.horizontal, 10)
                            .opacity(0.45)

                        // Bottom Half: AirPods / Bluetooth Audio
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
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(compactAudioLabel)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary.opacity(0.72))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onNavigate(.audioBluetooth)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassBentoCard(cornerRadius: 16)

                // Right Column: Battery Hero + Split Quick Tools
                VStack(spacing: 8) {
                    // Battery Hero Card
                    Button {
                        onNavigate(.battery)
                    } label: {
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
                                    .font(.system(size: 19, weight: .bold))
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
                                .frame(width: 36, height: 36)

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
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .glassBentoCard(cornerRadius: 16)
                        .opacity(batHover.isHovering ? 0.92 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { batHover.isHovering = $0 }

                    // Split Quick Tools (HiDPI + KeepAwake)
                    if moduleSettings.hidpiEnabled || moduleSettings.keepAwakeEnabled {
                        HStack(spacing: 7) {
                            if moduleSettings.hidpiEnabled {
                                Button {
                                    onNavigate(.display)
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: "display")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text("HiDPI")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .glassBentoCard(cornerRadius: 13)
                                    .opacity(hidpiHover.isHovering ? 0.9 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .onHover { hidpiHover.isHovering = $0 }
                            }

                            if moduleSettings.keepAwakeEnabled {
                                Button {
                                    onNavigate(.keepAwake)
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: keepAwakeStore.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(keepAwakeStore.isActive ? Color.orange : Color.primary)
                                        Text(keepAwakeStore.isActive ? "常亮中" : "防休眠")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(keepAwakeStore.isActive ? Color.orange : Color.primary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .glassBentoCard(cornerRadius: 13)
                                    .opacity(awakeHover.isHovering ? 0.9 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .onHover { awakeHover.isHovering = $0 }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)

            // 2. Tactile Control Center Volume Scrubber
            if moduleSettings.audioBluetoothEnabled {
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
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .glassBentoCard(cornerRadius: 16)
            }

            // 3. Clickable 3-Column System Telemetry Tile -> SystemTelemetryDetailView
            Button {
                onNavigate(.telemetry)
            } label: {
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
                .padding(.vertical, 9)
                .glassBentoCard(cornerRadius: 16)
                .opacity(telemetryHover.isHovering ? 0.92 : 1.0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { telemetryHover.isHovering = $0 }

            // 4. Integrated Utility Footer
            HStack {
                Button(action: onOpenConsole) {
                    Label("控制台", systemImage: "square.grid.2x2")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.9))
                }
                .buttonStyle(.plain)

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

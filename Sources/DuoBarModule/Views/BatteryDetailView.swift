import SwiftUI
import CoreKit

struct BatteryDetailView: View {
    @ObservedObject var store: DuoBarStore
    let onBack: () -> Void

    @StateObject private var lpmHover = HoverTracker()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubpageHeader(title: "电池", onBack: onBack) {
                Text(store.battery.isPluggedIn ? "电源供电" : "使用电池")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Circular Ring Hero Card
            HStack(spacing: 14) {
                ZStack {
                    CircularProgressRing(
                        progress: Double(store.battery.percentage) / 100.0,
                        lineWidth: 5.5,
                        color: store.battery.ringColor
                    )
                    .frame(width: 64, height: 64)

                    VStack(spacing: 1) {
                        if store.battery.showsChargingIndicator {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.green)
                        }
                        Text("\(store.battery.percentage)%")
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.battery.timeRemainingText)
                        .font(.system(size: 13.5, weight: .semibold))

                    if let telemetryLine = hardwareTelemetrySummary {
                        Text(telemetryLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }

                    Text("电源：\(store.battery.powerSourceLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(12)
            .glassBentoCard(cornerRadius: 18)

            // 2-Column Hardware Specs Bento
            if store.battery.hasBattery {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("电池健康度")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(store.battery.healthPercent)%")
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassBentoCard(cornerRadius: 14)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("循环次数")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(store.battery.cycleCount) 次")
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .glassBentoCard(cornerRadius: 14)
                }
            }

            // Tactile Low Power Mode Pill Card
            Button {
                store.toggleLowPowerMode()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        if store.battery.isLowPowerMode {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 28, height: 28)
                        } else {
                            GlassNeutralCircle(size: 28) { EmptyView() }
                        }
                        if store.isTogglingLPM {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "battery.25percent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(store.battery.isLowPowerMode ? Color.white : Color.primary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("低电量模式")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(store.battery.isLowPowerMode ? "已开启 · 降低后台能耗" : "已关闭")
                            .font(.system(size: 11))
                            .foregroundStyle(store.battery.isLowPowerMode ? Color.orange : Color.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { store.battery.isLowPowerMode },
                        set: { _ in store.toggleLowPowerMode() }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(HighlightRowStyle(hover: lpmHover, cornerRadius: 16))
            .glassBentoCard(cornerRadius: 16)

            HStack {
                Spacer()
                Button("电池设置…") {
                    store.openBatterySettings()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
    }

    private var hardwareTelemetrySummary: String? {
        if store.battery.isPluggedIn {
            var parts: [String] = []
            if let inputW = store.battery.systemPowerInWatts {
                parts.append(String(format: "输入 %.1f W", inputW))
            }
            if let loadW = store.battery.systemLoadWatts {
                parts.append(String(format: "整机 %.1f W", loadW))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        } else if let loadW = store.battery.systemLoadWatts {
            return String(format: "整机功耗 %.1f W", loadW)
        }
        return nil
    }
}

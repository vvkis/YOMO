import SwiftUI
import CoreKit

struct SystemTelemetryDetailView: View {
    @ObservedObject var store: DuoBarStore
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SubpageHeader(title: "系统占用", onBack: onBack) {
                Button {
                    store.openActivityMonitor()
                } label: {
                    Text("活动监视器")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.primary.opacity(0.11)))
                }
                .buttonStyle(.plain)
            }

            // 1. CPU / Memory / Disk Hardware Summary Bento Card
            VStack(alignment: .leading, spacing: 9) {
                // CPU Row + Mini Sparkline
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("CPU")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f%%", store.cpu.totalUsage))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(store.cpu.totalUsage >= 80 ? Color.red : Color.primary)
                                .monospacedDigit()
                        }
                        Text(String(format: "用户 %.0f%% · 系统 %.0f%% · 负载 %@", store.cpu.userUsage, store.cpu.systemUsage, store.cpu.loadAverage))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    MiniCPUSparkline(samples: store.cpu.history)
                        .frame(width: 66, height: 22)
                }

                Divider().opacity(0.45)

                // Memory Row + Segmented Usage Bar
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        HStack(spacing: 5) {
                            Text("内存")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f / %.0f GB", store.memory.usedGB, store.memory.totalGB))
                                .font(.system(size: 12.5, weight: .bold))
                                .monospacedDigit()
                        }
                        Spacer()
                        Text("压力 \(store.memory.pressureLevel.rawValue)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(pressureColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(pressureColor)
                    }

                    MemorySegmentedBar(
                        active: store.memory.activeGB,
                        wired: store.memory.wiredGB,
                        compressed: store.memory.compressedGB,
                        total: max(1, store.memory.totalGB)
                    )
                    .frame(height: 6)

                    HStack(spacing: 8) {
                        LegendDot(color: Color.accentColor, text: String(format: "App %.1fG", store.memory.activeGB))
                        LegendDot(color: Color.orange, text: String(format: "联动 %.1fG", store.memory.wiredGB))
                        LegendDot(color: Color.purple, text: String(format: "压缩 %.1fG", store.memory.compressedGB))
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }

                Divider().opacity(0.45)

                // Disk Row
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 5) {
                            Text("磁盘")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f / %.0f GB", store.disk.usedGB, store.disk.totalGB))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                        Spacer()
                        Text(String(format: "可用 %.0f GB", store.disk.availableGB))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    GeometryReader { geo in
                        let ratio = min(1.0, max(0.0, store.disk.usagePercent / 100.0))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule()
                                .fill(store.disk.usagePercent >= 88 ? Color.red : Color.primary.opacity(0.58))
                                .frame(width: max(4, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 5)
                }
            }
            .padding(11)
            .glassBentoCard(cornerRadius: 16)

            // 2. On-Demand Top Processes Card
            VStack(alignment: .leading, spacing: 7) {
                Picker("", selection: $store.telemetryTab) {
                    ForEach(TelemetrySortTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                let list = store.telemetryTab == .cpu ? store.topCPUProcesses : store.topMemoryProcesses

                if store.isLoadingProcesses && list.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在采样进程占用…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                } else if list.isEmpty {
                    Text("暂无高占用进程")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                } else {
                    VStack(spacing: 4) {
                        ForEach(list) { proc in
                            ProcessStatRow(
                                item: proc,
                                mode: store.telemetryTab
                            )
                        }
                    }
                }
            }
            .padding(10)
            .glassBentoCard(cornerRadius: 16)
        }
        .padding(14)
    }

    private var pressureColor: Color {
        switch store.memory.pressureLevel {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private struct ProcessStatRow: View {
    let item: ProcessStatItem
    let mode: TelemetrySortTab

    var body: some View {
        HStack(spacing: 7) {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }

            Text(item.name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(mode == .cpu ? item.formattedCPU : item.formattedMemory)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(metricColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2.5)
    }

    private var metricColor: Color {
        if mode == .cpu {
            if item.cpuPercent >= 50 { return .red }
            if item.cpuPercent >= 20 { return .orange }
            return .primary
        } else {
            let gb = Double(item.memoryBytes) / 1_073_741_824.0
            if gb >= 2.0 { return .orange }
            return .primary
        }
    }
}

private struct MiniCPUSparkline: View {
    let samples: [Double]

    var body: some View {
        let slice = Array(samples.suffix(16))
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(slice.enumerated()), id: \.offset) { _, val in
                let ratio = min(1.0, max(0.12, val / 100.0))
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(val >= 80 ? Color.red : Color.accentColor.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2.5, 22 * ratio))
            }
        }
    }
}

private struct MemorySegmentedBar: View {
    let active: Double
    let wired: Double
    let compressed: Double
    let total: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let aW = max(0, min(w, w * (active / total)))
            let wW = max(0, min(w - aW, w * (wired / total)))
            let cW = max(0, min(w - aW - wW, w * (compressed / total)))

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                HStack(spacing: 1) {
                    if aW > 0 {
                        Rectangle().fill(Color.accentColor).frame(width: aW)
                    }
                    if wW > 0 {
                        Rectangle().fill(Color.orange).frame(width: wW)
                    }
                    if cW > 0 {
                        Rectangle().fill(Color.purple).frame(width: cW)
                    }
                }
                .clipShape(Capsule())
            }
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 3.5) {
            Circle()
                .fill(color)
                .frame(width: 5.5, height: 5.5)
            Text(text)
                .lineLimit(1)
        }
    }
}

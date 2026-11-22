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

            // 2. On-Demand Top Processes & Listening Port Radar Card
            VStack(alignment: .leading, spacing: 7) {
                Picker("", selection: $store.telemetryTab) {
                    ForEach(TelemetrySortTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if store.telemetryTab == .ports {
                    portRadarSection
                } else {
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
            }
            .padding(10)
            .glassBentoCard(cornerRadius: 16)
        }
        .padding(14)
    }

    @ViewBuilder
    private var portRadarSection: some View {
        // Compact Port / Process Search Bar
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("输入端口号或进程名，如 3000、node…", text: $store.portSearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
            if !store.portSearchQuery.isEmpty {
                Button {
                    store.portSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                store.refreshListeningPorts()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("立即重新扫描本机监听端口")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )

        if let feedback = store.portActionFeedback {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text(feedback)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.14))
            )
        }

        let ports = store.filteredListeningPorts
        if store.isLoadingPorts && store.listeningPorts.isEmpty {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("正在扫描本机监听端口…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
        } else if let exactPort = store.parsedSearchedPort, !ports.contains(where: { $0.port == exactPort }) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                    Text("端口 :\(exactPort) 当前空闲")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
                Text("未检测到本机 TCP 进程监听此端口，可直接使用")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button {
                    store.copySudoCommand(
                        "sudo lsof -nP -iTCP:\(exactPort) -sTCP:LISTEN",
                        label: "已复制 :\(exactPort) 的 sudo 排查命令"
                    )
                } label: {
                    Text("复制 sudo 排查命令")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if ports.isEmpty {
            Text(store.portSearchQuery.isEmpty ? "当前无监听中的 TCP 端口" : "未找到匹配的监听端口")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(ports) { item in
                        ListeningPortRow(
                            item: item,
                            isArmed: store.pendingKillPortID == item.id,
                            isForceKill: item.pid.map { store.forceKillEligiblePIDs.contains($0) } ?? false,
                            onKillOrConfirm: {
                                store.requestOrConfirmKill(item)
                            },
                            onCopySudoKill: {
                                store.copySudoCommand(item.sudoKillCommand, label: "已复制 :\(item.port) 的 sudo 终止命令")
                            },
                            onCopySudoInspect: {
                                store.copySudoCommand(item.sudoInspectCommand, label: "已复制 :\(item.port) 的 sudo 查看命令")
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: 196)

            HStack {
                Text("共 \(ports.count) 个监听端口")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                Text("root 进程支持一键复制 sudo 命令")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)
        }
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

private struct ListeningPortRow: View {
    let item: ListeningPortItem
    let isArmed: Bool
    let isForceKill: Bool
    let onKillOrConfirm: () -> Void
    let onCopySudoKill: () -> Void
    let onCopySudoInspect: () -> Void

    @StateObject private var hover = HoverTracker()

    var body: some View {
        HStack(spacing: 7) {
            // Left Port Badge
            Text(":\(item.port)")
                .font(.system(size: 10.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(portBadgeForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(minWidth: 46)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(portBadgeBackground)
                )

            // Middle: Process Info & Bind Scope
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 4) {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 13, height: 13)
                    } else if item.requiresSudo {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    Text(item.processName)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 3.5) {
                    Text(item.bindScopeLabel)
                        .foregroundStyle(item.isLoopbackOnly ? Color.secondary : Color.accentColor)
                    Text("·")
                    Text(item.bindAddress)
                        .lineLimit(1)
                    if let pid = item.pid {
                        Text("·")
                        Text("PID \(pid)")
                    }
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            }

            Spacer(minLength: 2)

            // Right Action: Copy sudo commands for root processes, or 2-step Kill for user processes
            if item.requiresSudo {
                HStack(spacing: 4) {
                    Button(action: onCopySudoInspect) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("复制查看命令：\(item.sudoInspectCommand)")

                    Button(action: onCopySudoKill) {
                        Text("复制 sudo")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .help("复制终止命令：\(item.sudoKillCommand)")
                }
            } else if item.isSelfProcess {
                Text("本应用")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            } else {
                Button(action: onKillOrConfirm) {
                    Text(isArmed ? (isForceKill ? "确认强杀" : "确认?") : (isForceKill ? "强杀" : "结束"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isArmed ? Color.white : Color.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule().fill(isArmed ? Color.red : Color.red.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .help(isArmed ? "再次点击立即结束 PID \(item.pid ?? 0)" : "点击后二次确认结束进程（SIGTERM）")
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hover.isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hover.isHovering = $0 }
    }

    private var portBadgeForeground: Color {
        if item.requiresSudo { return .orange }
        if !item.isLoopbackOnly { return Color.accentColor }
        return .primary
    }

    private var portBadgeBackground: Color {
        if item.requiresSudo { return Color.orange.opacity(0.15) }
        if !item.isLoopbackOnly { return Color.accentColor.opacity(0.15) }
        return Color.primary.opacity(0.08)
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

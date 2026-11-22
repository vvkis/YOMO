import SwiftUI
import CoreKit

public struct KeepAwakePopoverView: View {
    @ObservedObject public var store: KeepAwakeStore
    public let onBack: () -> Void

    public init(store: KeepAwakeStore, onBack: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubpageHeader(title: "防休眠", onBack: onBack) {
                Toggle("", isOn: Binding(
                    get: { store.isActive },
                    set: { $0 ? store.activate(duration: store.selectedDuration) : store.deactivate() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            // Status Hero Card
            HStack(spacing: 12) {
                ZStack {
                    if store.isActive {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 44, height: 44)
                    } else {
                        GlassNeutralCircle(size: 44) { EmptyView() }
                    }
                    Image(systemName: store.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(store.isActive ? Color.white : Color.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isActive ? "防休眠已开启" : "防休眠已关闭")
                        .font(.system(size: 13.5, weight: .bold))
                    Text(store.isActive ? store.statusSubtitle : "点击下方任意时长立即阻止息屏")
                        .font(.system(size: 11))
                        .foregroundStyle(store.isActive ? Color.orange : Color.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(12)
            .glassBentoCard(cornerRadius: 18)

            // 2x2 Tactile Duration Grid
            let timedDurations = KeepAwakeDuration.allCases.filter { $0 != .indefinite }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                ForEach(timedDurations) { duration in
                    KeepAwakeDurationTile(
                        title: duration.label,
                        isSelected: store.isActive && store.selectedDuration == duration
                    ) {
                        store.activate(duration: duration)
                    }
                }
            }

            // Full-width Indefinite Tile
            KeepAwakeDurationTile(
                title: "∞ 持续防息屏直到手动关闭",
                isSelected: store.isActive && store.selectedDuration == .indefinite,
                centered: true
            ) {
                store.activate(duration: .indefinite)
            }
        }
        .padding(14)
    }
}

private struct KeepAwakeDurationTile: View {
    let title: String
    let isSelected: Bool
    var centered: Bool = false
    let action: () -> Void
    @StateObject private var hover = HoverTracker()

    var body: some View {
        Button(action: action) {
            HStack {
                if centered { Spacer() }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                if centered { Spacer() }
                if !centered && isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.orange)
                    } else {
                        Color.clear.glassBentoCard(cornerRadius: 13)
                    }
                }
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .opacity(!isSelected && hover.isHovering ? 0.88 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
    }
}

public struct KeepAwakeConsoleView: View {
    @ObservedObject public var store: KeepAwakeStore
    @ObservedObject public var moduleSettings: ModuleSettings

    public init(store: KeepAwakeStore, moduleSettings: ModuleSettings) {
        self.store = store
        self.moduleSettings = moduleSettings
    }

    public var body: some View {
        ConsolePageContainer(
            title: "防休眠",
            subtitle: "基于 IOKit 原生内核超时断言阻止屏幕息屏与系统休眠，关闭或超时即自动释放。",
            trailing: {
                HStack(spacing: 8) {
                    Text("启用模块")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    ConsoleSwitch(isOn: Binding(
                        get: { moduleSettings.keepAwakeEnabled },
                        set: { enabled in
                            moduleSettings.keepAwakeEnabled = enabled
                            if !enabled { store.deactivate() }
                        }
                    ))
                }
            }
        ) {
            ConsoleCard("当前状态") {
                ConsoleRow(
                    title: store.isActive ? "防休眠运行中" : "防休眠未开启",
                    subtitle: store.statusSubtitle
                ) {
                    ConsoleActionButton(
                        store.isActive ? "立即关闭" : "立即开启",
                        variant: store.isActive ? .standard : .prominent,
                        disabled: !moduleSettings.keepAwakeEnabled
                    ) {
                        store.toggle()
                    }
                }
            }

            ConsoleCard("持续时长") {
                ForEach(Array(KeepAwakeDuration.allCases.enumerated()), id: \.element.id) { idx, duration in
                    if idx > 0 {
                        ConsoleRowDivider()
                    }
                    ConsoleRadioRow(
                        title: duration.label,
                        subtitle: duration == .indefinite ? "保持常亮直到手动关闭或退出 YOMO" : "到期后内核自动回收断言并恢复系统节能",
                        isSelected: store.isActive && store.selectedDuration == duration
                    ) {
                        guard moduleSettings.keepAwakeEnabled else { return }
                        store.activate(duration: duration)
                    }
                }
            }
        }
    }
}

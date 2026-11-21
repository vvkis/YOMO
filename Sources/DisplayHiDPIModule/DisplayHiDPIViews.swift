import SwiftUI
import CoreKit

public struct DisplayHiDPIPopoverView: View {
    @ObservedObject public var store: DisplayHiDPIStore
    public let onBack: () -> Void
    public let onOpenConsole: () -> Void

    public init(store: DisplayHiDPIStore, onBack: @escaping () -> Void, onOpenConsole: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
        self.onOpenConsole = onOpenConsole
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubpageHeader(title: "显示器 / HiDPI", onBack: onBack) {
                if store.canRevert {
                    Button {
                        store.revertLastMode()
                    } label: {
                        Text("恢复上一档")
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.primary.opacity(0.11)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.displays.count > 1 {
                Picker("", selection: Binding(
                    get: { store.selectedDisplayID ?? store.displays.first?.id ?? 0 },
                    set: { store.selectedDisplayID = $0 }
                )) {
                    ForEach(store.displays) { d in
                        Text(d.name).tag(d.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let display = store.selectedDisplay {
                // 1. Monitor Hero Card
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(display.currentIsHiDPI ? Color.accentColor : Color.primary.opacity(0.6), lineWidth: 1.8)
                        .frame(width: 42, height: 30)
                        .overlay(
                            HStack(spacing: 1) {
                                if display.currentIsHiDPI {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8.5, weight: .bold))
                                    Text("Hi")
                                        .font(.system(size: 10, weight: .bold))
                                } else {
                                    Text("普通")
                                        .font(.system(size: 9.5, weight: .semibold))
                                }
                            }
                            .foregroundStyle(display.currentIsHiDPI ? Color.accentColor : Color.primary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Text(display.currentSummary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))
                            .monospacedDigit()
                        Text(display.panelSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassBentoCard(cornerRadius: 15)

                // 2. Refresh Rate Pills (single-line, never wraps "Hz")
                if display.refreshRateModes.count > 1 {
                    HStack(spacing: 6) {
                        Text("刷新率")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(display.refreshRateModes) { hzMode in
                                    Button {
                                        store.applyMode(hzMode, for: display.id)
                                    } label: {
                                        Text("\(hzMode.refreshRate)Hz")
                                            .font(.system(size: 10, weight: hzMode.isCurrent ? .bold : .medium))
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .padding(.horizontal, 6.5)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule().fill(hzMode.isCurrent ? Color.accentColor : Color.primary.opacity(0.08))
                                            )
                                            .foregroundStyle(hzMode.isCurrent ? Color.white : Color.primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassBentoCard(cornerRadius: 12)
                }

                // 3. HiDPI Filter Toggle (matches BetterDisplay: HiDPI only vs HiDPI + LoDPI)
                Picker("", selection: $store.modeFilter) {
                    ForEach(DisplayModeFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // 4. BetterDisplay-style Resolution List Card
                VStack(alignment: .leading, spacing: 4) {
                    if let defMode = display.defaultNativeMode {
                        Text("默认及原生模式")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.top, 2)

                        DisplayModeRow(mode: defMode, showStarForDefault: true) {
                            store.applyMode(defMode, for: display.id)
                        }

                        Divider()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .opacity(0.45)
                    }

                    HStack {
                        Text(store.modeFilter == .hiDPIOnly ? "HiDPI 高清模式" : "全部模式（HiDPI 与普通）")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(display.filteredModes(filter: store.modeFilter, includeOtherAspects: store.showOtherAspects).count) 档")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 6)

                    let modes = display.filteredModes(filter: store.modeFilter, includeOtherAspects: store.showOtherAspects)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 1.5) {
                            ForEach(modes) { mode in
                                DisplayModeRow(mode: mode, showStarForDefault: false) {
                                    store.applyMode(mode, for: display.id)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 192)
                }
                .padding(7)
                .glassBentoCard(cornerRadius: 15)

                if !display.otherAspectModes.isEmpty {
                    Toggle("显示其他屏幕比例（4:3 / 16:10 等）", isOn: $store.showOtherAspects)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }
            }

            HStack {
                Button("高级控制台…") {
                    onOpenConsole()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer()

                Button("显示设置…") {
                    store.openDisplaySettings()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .onAppear {
            store.refreshDisplays()
        }
    }
}

private struct DisplayModeRow: View {
    let mode: DisplayModeOption
    let showStarForDefault: Bool
    let action: () -> Void
    @StateObject private var hover = HoverTracker()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                // Status indicator (matches BetterDisplay's checkmark / star / ring)
                Group {
                    if mode.isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    } else if showStarForDefault || mode.isDefault {
                        Image(systemName: "star.circle")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.75))
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.65))
                    }
                }
                .frame(width: 16)

                Text(mode.resolutionText)
                    .font(.system(size: 12.5, weight: mode.isCurrent ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)

                Spacer(minLength: 4)

                // HiDPI Sparkle badge (exact BetterDisplay semantics)
                if mode.isHiDPI {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(mode.isCurrent ? Color.accentColor : Color.primary.opacity(0.72))
                        .help("HiDPI 高清渲染 (\(mode.pixelText))")
                } else {
                    Text("普通")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                // Compact Aspect + Refresh pills
                HStack(spacing: 3) {
                    if !mode.aspectRatioLabel.isEmpty {
                        MetaPill(text: mode.aspectRatioLabel)
                    }
                    if mode.refreshRate > 0 {
                        MetaPill(text: "\(mode.refreshRate)Hz")
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowStyle(hover: hover, cornerRadius: 9))
    }
}

private struct MetaPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }
}

public struct DisplayHiDPIConsoleView: View {
    @ObservedObject public var store: DisplayHiDPIStore
    @ObservedObject public var moduleSettings: ModuleSettings

    public init(store: DisplayHiDPIStore, moduleSettings: ModuleSettings) {
        self.store = store
        self.moduleSettings = moduleSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text("通过 macOS 系统显示引擎（MonitorPanel）直接列出全部原生 HiDPI 与普通档位及高刷刷新率，免重启即刻切换。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("在菜单栏显示", isOn: $moduleSettings.hidpiEnabled)
                        .toggleStyle(.switch)
                }

                if let msg = store.statusMessage {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(msg)
                            .font(.callout)
                        Spacer()
                        if store.canRevert {
                            Button("恢复上一分辨率") {
                                store.revertLastMode()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }

                ForEach(store.displays) { display in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(display.name)
                                            .font(.headline)
                                        if display.isMain {
                                            Text("主显示器")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    Text("当前 \(display.currentSummary) · \(display.panelSubtitle) · Vendor 0x\(display.vendorHex) / Product 0x\(display.productHex)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Spacer()
                                Button("刷新") {
                                    store.refreshDisplays()
                                }
                                .controlSize(.small)
                            }

                            HStack(spacing: 12) {
                                Picker("", selection: $store.modeFilter) {
                                    ForEach(DisplayModeFilter.allCases) { f in
                                        Text(f.rawValue).tag(f)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 210)

                                if display.refreshRateModes.count > 1 {
                                    HStack(spacing: 6) {
                                        Text("刷新率")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        ForEach(display.refreshRateModes) { hzMode in
                                            Button("\(hzMode.refreshRate)Hz") {
                                                store.applyMode(hzMode, for: display.id)
                                            }
                                            .buttonStyle(.bordered)
                                            .tint(hzMode.isCurrent ? .accentColor : .secondary)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                                Spacer()
                            }

                            Divider()

                            let modes = display.filteredModes(filter: store.modeFilter, includeOtherAspects: store.showOtherAspects)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 8)], spacing: 8) {
                                ForEach(modes) { mode in
                                    Button {
                                        store.applyMode(mode, for: display.id)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(mode.resolutionText)
                                                .font(.system(size: 12, weight: mode.isCurrent ? .bold : .medium))
                                                .monospacedDigit()
                                            Spacer()
                                            if mode.isHiDPI {
                                                Image(systemName: "sparkles")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                            Text(mode.isHiDPI ? "HiDPI" : "普通")
                                                .font(.caption2.weight(.semibold))
                                            if mode.refreshRate > 0 {
                                                Text("\(mode.refreshRate)Hz")
                                                    .font(.caption2)
                                                    .opacity(0.8)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(mode.isCurrent ? Color.accentColor : Color.primary.opacity(0.06))
                                        )
                                        .foregroundStyle(mode.isCurrent ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(6)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .onAppear {
            store.refreshDisplays()
        }
    }
}

import SwiftUI
import CoreKit

struct SettingsDetailView: View {
    @ObservedObject var store: DuoBarStore
    @ObservedObject var prefs: AppPreferences
    @ObservedObject var moduleSettings: ModuleSettings
    @ObservedObject var updateStore: AppUpdateStore
    let onBack: () -> Void
    let onOpenConsole: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SubpageHeader(title: "外观与样式", onBack: onBack)

            // Glass Appearance Mode
            VStack(alignment: .leading, spacing: 6) {
                Text("玻璃外观")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                Picker("", selection: Binding(
                    get: { moduleSettings.glassAppearance },
                    set: { moduleSettings.glassAppearance = $0 }
                )) {
                    ForEach(GlassAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(10)
            .glassBentoCard(cornerRadius: 15)

            // Icon Style Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("菜单栏图标样式")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(BadgeStyle.allCases) { style in
                        let selected = (prefs.badgeStyle == style)
                        Button {
                            prefs.badgeStyle = style
                        } label: {
                            Text(style.title)
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.08))
                                )
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
            .glassBentoCard(cornerRadius: 15)

            // Switches & Refresh
            VStack(spacing: 9) {
                Toggle(isOn: $prefs.semanticColor) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("图标语义配色")
                            .font(.system(size: 12, weight: .medium))
                        Text("关闭后使用自适应纯单色模板")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if prefs.badgeStyle == .capsule {
                    Divider().opacity(0.45)

                    Toggle(isOn: $prefs.showBatteryPercentInRing) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("电量环顶部显示百分比")
                                .font(.system(size: 12, weight: .medium))
                            Text("断开圆环顶部缺口嵌入实时电量数字")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                Divider().opacity(0.45)

                HStack {
                    Text("刷新频率")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $prefs.refreshInterval) {
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                        Text("3 秒").tag(3.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 136)
                    .labelsHidden()
                }

                Divider().opacity(0.45)

                Toggle(isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                )) {
                    Text("开机自动启动")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider().opacity(0.45)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("版本 \(updateStore.displayCurrentVersion)")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                        Text(popoverUpdateSubtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(updateStore.hasUpdateAvailable ? ConsoleTheme.accent : Color.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if updateStore.hasUpdateAvailable {
                        Button("去升级") {
                            onOpenConsole()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(ConsoleTheme.accent))
                    } else if case .checking = updateStore.state {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.75)
                    } else {
                        Button("检查更新") {
                            updateStore.checkForUpdates(userInitiated: true)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.09)))
                    }
                }
            }
            .padding(10)
            .glassBentoCard(cornerRadius: 15)
        }
        .padding(14)
        .onAppear {
            store.refreshLaunchAtLoginState()
        }
    }

    private var popoverUpdateSubtitle: String {
        switch updateStore.state {
        case .idle:
            return "原地升级，保留全部配置"
        case .checking:
            return "正在连接 GitHub Releases…"
        case .upToDate:
            return "已是最新版本"
        case .available(let release):
            return "发现新版本 \(release.displayVersion)"
        case .downloading(_, let progress, _, _):
            return "正在下载更新 \(Int(round(progress * 100)))%"
        case .verifying:
            return "正在校验安装包完整性…"
        case .readyToInstall(let release, _, _, _):
            return "\(release.displayVersion) 已就绪，前往升级"
        case .installing:
            return "正在替换并重启…"
        case .failed(let msg):
            return msg
        }
    }
}

import SwiftUI
import CoreKit

struct SettingsDetailView: View {
    @ObservedObject var store: DuoBarStore
    @ObservedObject var prefs: AppPreferences
    @ObservedObject var moduleSettings: ModuleSettings
    let onBack: () -> Void

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
            }
            .padding(10)
            .glassBentoCard(cornerRadius: 15)
        }
        .padding(14)
    }
}

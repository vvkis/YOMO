import SwiftUI
import CoreKit

public struct DuoBarConsoleView: View {
    @ObservedObject public var store: DuoBarStore
    @ObservedObject public var prefs: AppPreferences

    public init(store: DuoBarStore) {
        self.store = store
        self.prefs = store.prefs
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("灵感源自 iPhone Duo 的紧凑状态聚合，单枚图标融合电量、Wi-Fi、存储水位与实时网速。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox("菜单栏外观与指标") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("图标样式")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { prefs.badgeStyle },
                                set: { prefs.badgeStyle = $0 }
                            )) {
                                ForEach(BadgeStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        Toggle("语义配色（充电绿 / 低电红 / 正常水位纯净白）", isOn: $prefs.semanticColor)
                            .toggleStyle(.switch)

                        HStack {
                            Text("采样刷新间隔")
                            Spacer()
                            Picker("", selection: $prefs.refreshInterval) {
                                Text("1 秒").tag(1.0)
                                Text("2 秒").tag(2.0)
                                Text("3 秒").tag(3.0)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            .labelsHidden()
                        }

                        Toggle("开机自动启动 YOMO", isOn: Binding(
                            get: { store.launchAtLogin },
                            set: { store.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.switch)
                    }
                    .padding(8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }
}

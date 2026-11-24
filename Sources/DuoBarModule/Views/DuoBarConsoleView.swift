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
        ConsolePageContainer(
            title: "状态栏",
            subtitle: "单枚紧凑图标聚合电量、Wi-Fi、内存水位与实时网速，双屏静态预渲染零空转。"
        ) {
            // Card 1: Radio-style Badge Style Selector (WeChat Input top card aesthetic)
            ConsoleCard("图标样式") {
                ForEach(Array(BadgeStyle.allCases.enumerated()), id: \.element.id) { idx, style in
                    if idx > 0 {
                        ConsoleRowDivider()
                    }
                    ConsoleRadioRow(
                        title: style.title,
                        subtitle: styleDescription(style),
                        isSelected: prefs.badgeStyle == style
                    ) {
                        prefs.badgeStyle = style
                    }
                }
            }

            // Card 2: Appearance & Visual Details
            ConsoleCard("显示细节") {
                ConsoleRow(
                    title: "语义配色",
                    subtitle: "充电与健康电量显绿、低电量警示红橙，正常水位保持纯净前景色"
                ) {
                    ConsoleSwitch(isOn: $prefs.semanticColor)
                }

                if prefs.badgeStyle == .capsule {
                    ConsoleRowDivider()

                    ConsoleRow(
                        title: "电量环顶部断开显示百分比",
                        subtitle: "iPhone Duo 风格：在圆环 12 点位置嵌入等宽窄体电量数字"
                    ) {
                        ConsoleSwitch(isOn: $prefs.showBatteryPercentInRing)
                    }
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "菜单栏靠右置顶",
                    subtitle: "优先停靠在第三方图标最右侧（靠近控制中心），不易被其他应用挤到左侧或刘海后；关闭后可按住 ⌘ 自由拖动"
                ) {
                    HStack(spacing: 10) {
                        if prefs.pinStatusItemRight {
                            ConsoleActionButton("移到最右") {
                                store.reapplyStatusItemPosition()
                            }
                        }
                        ConsoleSwitch(isOn: Binding(
                            get: { prefs.pinStatusItemRight },
                            set: { enabled in
                                prefs.pinStatusItemRight = enabled
                                if enabled {
                                    store.reapplyStatusItemPosition()
                                }
                            }
                        ))
                    }
                }
            }

            // Card 3: Refresh & Startup
            ConsoleCard("采样与启动") {
                ConsoleRow(
                    title: "状态栏采样间隔",
                    subtitle: "仅更新轻量内核计数器，息屏休眠时自动暂停采样"
                ) {
                    Picker("", selection: $prefs.refreshInterval) {
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                        Text("3 秒").tag(3.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                    .labelsHidden()
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "开机自动启动 YOMO",
                    subtitle: "登录后自动常驻菜单栏，随时一键呼出工具面板"
                ) {
                    ConsoleSwitch(isOn: Binding(
                        get: { store.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    ))
                }
            }
        }
        .onAppear {
            store.refreshLaunchAtLoginState()
        }
    }

    private func styleDescription(_ style: BadgeStyle) -> String {
        switch style {
        case .capsule: return "左侧电量 Wi-Fi 圆环 + 右侧双行内存与实时网速（推荐）"
        case .dualRing: return "外环电量、内环 CPU，中心直读内存百分比"
        case .triArc: return "三段弧线分别映射电量、内存与 CPU，中心显示 Wi-Fi"
        case .splitArc: return "左右双弧对比电量与内存，中心显示 Wi-Fi"
        }
    }
}

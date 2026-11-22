import SwiftUI
import CoreKit

public struct KeyboardLockConsoleView: View {
    @ObservedObject public var store: KeyboardLockStore
    @ObservedObject public var moduleSettings: ModuleSettings

    public init(store: KeyboardLockStore, moduleSettings: ModuleSettings) {
        self.store = store
        self.moduleSettings = moduleSettings
    }

    public var body: some View {
        ConsolePageContainer(
            title: "键盘锁",
            subtitle: "清理键盘时一键拦截全部按键与顶部亮度/音量媒体键，鼠标与触控板保持可用，未锁定时零后台监听。",
            trailing: {
                HStack(spacing: 8) {
                    Text("启用模块")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    ConsoleSwitch(isOn: Binding(
                        get: { moduleSettings.keyboardLockEnabled },
                        set: { enabled in
                            moduleSettings.keyboardLockEnabled = enabled
                            store.syncWithModuleEnabled(enabled)
                        }
                    ))
                }
            }
        ) {
            if !store.hasAccessibilityPermission {
                ConsoleBanner(
                    icon: "exclamationmark.shield.fill",
                    tint: .orange,
                    title: "需要辅助功能权限",
                    subtitle: "请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 YOMO（与滚轮翻转共享同一权限）。"
                ) {
                    HStack(spacing: 6) {
                        ConsoleActionButton("刷新") {
                            store.refreshPermissionState()
                        }
                        ConsoleActionButton("前往授权", variant: .prominent) {
                            store.requestAccessibilityPermission()
                            store.openAccessibilitySettings()
                        }
                    }
                }
            }

            ConsoleCard("当前状态") {
                ConsoleRow(
                    title: store.isLocked ? "键盘已锁定（清洁模式运行中）" : "键盘未锁定",
                    subtitle: store.statusMessage ?? store.statusSubtitle
                ) {
                    ConsoleActionButton(
                        store.isLocked ? "立即解锁" : "锁定键盘",
                        variant: store.isLocked ? .destructive : .prominent,
                        disabled: !moduleSettings.keyboardLockEnabled
                    ) {
                        store.toggle()
                    }
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "辅助功能权限",
                    subtitle: store.hasAccessibilityPermission ? "已授权，随时可一键锁定键盘输入" : "尚未授权，无法安装全局按键拦截器"
                ) {
                    HStack(spacing: 8) {
                        Text(store.hasAccessibilityPermission ? "已授权" : "未授权")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(store.hasAccessibilityPermission ? ConsoleTheme.accent : .orange)
                        ConsoleActionButton("刷新") {
                            store.refreshPermissionState()
                        }
                    }
                }
            }

            ConsoleCard("安全解锁保障") {
                ConsoleRow(
                    title: "悬浮条一键解锁",
                    subtitle: "锁定时屏幕底部会浮现深色解锁胶囊，鼠标与触控板始终可用"
                ) {
                    Image(systemName: "cursorarrow.click")
                        .foregroundStyle(.secondary)
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "紧急快捷键解锁",
                    subtitle: "即使没有鼠标，同时按下组合键即可立即强制解除锁定"
                ) {
                    Text("⌃⌥⌘U")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                }

                ConsoleRowDivider()

                ConsoleRow(
                    title: "休眠与退出自动恢复",
                    subtitle: "Mac 进入休眠或退出 YOMO 时自动撤销拦截，绝不锁死系统"
                ) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(ConsoleTheme.accent)
                }
            }
        }
        .onAppear {
            store.refreshPermissionState()
        }
    }
}

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text("清理键盘时一键拦截全部键盘按键与顶部功能/媒体键（亮度、音量、播放等），鼠标与触控板保持可用，未开启时零后台事件拦截。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("启用模块", isOn: Binding(
                        get: { moduleSettings.keyboardLockEnabled },
                        set: { enabled in
                            moduleSettings.keyboardLockEnabled = enabled
                            store.syncWithModuleEnabled(enabled)
                        }
                    ))
                    .toggleStyle(.switch)
                }

                GroupBox("当前状态") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill((store.isLocked ? Color.orange : Color.secondary).opacity(0.16))
                                    .frame(width: 40, height: 40)
                                Image(systemName: store.isLocked ? "lock.fill" : "keyboard")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(store.isLocked ? Color.orange : Color.primary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.isLocked ? "键盘已锁定（清洁模式运行中）" : "键盘未锁定")
                                    .font(.headline)
                                Text(store.statusSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(store.isLocked ? "立即解锁" : "锁定键盘") {
                                store.toggle()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(store.isLocked ? .orange : .accentColor)
                            .disabled(!moduleSettings.keyboardLockEnabled)
                        }

                        if let msg = store.statusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Divider()

                        HStack {
                            Image(systemName: store.hasAccessibilityPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .foregroundStyle(store.hasAccessibilityPermission ? .green : .orange)
                            Text(store.hasAccessibilityPermission ? "已获得辅助功能权限（与鼠标滚轮翻转共享）" : "需要「辅助功能」权限以拦截全局键盘按键")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !store.hasAccessibilityPermission {
                                Button("打开辅助功能设置") {
                                    store.openAccessibilitySettings()
                                }
                                .controlSize(.small)
                            }
                            Button("刷新状态") {
                                store.refreshPermissionState()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(6)
                }

                GroupBox("安全解锁方式") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("点击屏幕底部浮现的「解锁」悬浮条（鼠标 / 触控板始终可用）", systemImage: "cursorarrow.click")
                        Label("再次点击菜单栏 YOMO 面板中的「键盘锁」小按钮", systemImage: "menubar.rectangle")
                        Label("紧急键盘快捷键：同时按下 ⌃⌥⌘U 强制解锁", systemImage: "command")
                        Label("Mac 休眠或退出 YOMO 时自动解除锁定，绝不会锁死系统", systemImage: "shield.lefthalf.filled")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .onAppear {
            store.refreshPermissionState()
        }
    }
}

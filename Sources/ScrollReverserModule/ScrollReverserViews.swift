import SwiftUI
import CoreKit

public struct ScrollReverserPopoverView: View {
    @ObservedObject public var store: ScrollReverserStore
    public let onBack: () -> Void

    public init(store: ScrollReverserStore, onBack: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubpageHeader(title: "鼠标滚轮翻转", onBack: onBack) {
                Toggle("", isOn: Binding(
                    get: { store.isActive },
                    set: { store.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            // 1. Status Hero Card
            HStack(spacing: 12) {
                ZStack {
                    if store.isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 44, height: 44)
                    } else {
                        GlassNeutralCircle(size: 44) { EmptyView() }
                    }
                    Image(systemName: store.isActive ? "computermouse.fill" : "computermouse")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(store.isActive ? Color.white : Color.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isActive ? "滚轮翻转已开启" : "滚轮翻转已关闭")
                        .font(.system(size: 13.5, weight: .bold))
                    Text(store.isActive ? store.statusSubtitle : "外接鼠标改为传统滚动，触控板保持自然滚动")
                        .font(.system(size: 11))
                        .foregroundStyle(store.isActive ? Color.accentColor : Color.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .glassBentoCard(cornerRadius: 18)

            // 2. Accessibility Permission Banner (only when not yet trusted)
            if !store.hasAccessibilityPermission {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("需要辅助功能权限")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("授权后即可仅翻转外接鼠标滚轮方向")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("前往授权") {
                        store.requestAccessibilityPermission()
                        store.openAccessibilitySettings()
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(10)
                .glassBentoCard(cornerRadius: 14)
            }

            // 3. Reversal Options Bento Card
            VStack(spacing: 9) {
                Toggle(isOn: $store.mouseOnly) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("仅翻转鼠标滚轮")
                            .font(.system(size: 12, weight: .medium))
                        Text("保留 Mac 触控板原生自然滚动")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider().opacity(0.45)

                Toggle(isOn: $store.reverseVertical) {
                    Text("翻转垂直滚轮（上下滚动）")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider().opacity(0.45)

                Toggle(isOn: $store.reverseHorizontal) {
                    Text("翻转水平滚轮（左右倾斜/侧滚轮）")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(11)
            .glassBentoCard(cornerRadius: 16)

            if let msg = store.statusMessage {
                Text(msg)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            }

            HStack {
                Spacer()
                Button("辅助功能设置…") {
                    store.openAccessibilitySettings()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .onAppear {
            store.refreshPermissionState()
        }
    }
}

public struct ScrollReverserConsoleView: View {
    @ObservedObject public var store: ScrollReverserStore
    @ObservedObject public var moduleSettings: ModuleSettings

    public init(store: ScrollReverserStore, moduleSettings: ModuleSettings) {
        self.store = store
        self.moduleSettings = moduleSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text("基于 Quartz CGEventTap 原生拦截离散鼠标滚轮事件，让外接鼠标使用传统滚动方向，同时保留触控板自然滚动。关闭时完全销毁监听，零后台开销。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("启用模块", isOn: Binding(
                        get: { moduleSettings.scrollReverserEnabled },
                        set: { enabled in
                            moduleSettings.scrollReverserEnabled = enabled
                            store.syncWithModuleEnabled(enabled)
                        }
                    ))
                    .toggleStyle(.switch)
                }

                if !store.hasAccessibilityPermission {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.raised.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("尚未获得辅助功能权限")
                                .font(.subheadline.bold())
                            Text("macOS 要求在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 YOMO 后，才允许翻转鼠标滚轮方向。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("前往授权") {
                            store.requestAccessibilityPermission()
                            store.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(store.isActive ? "滚轮翻转已开启" : "滚轮翻转未开启", systemImage: store.isActive ? "computermouse.fill" : "computermouse")
                                .font(.headline)
                                .foregroundStyle(store.isActive ? Color.accentColor : .primary)
                            Spacer()
                            Text(store.statusSubtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button(store.isActive ? "立即关闭" : "立即开启") {
                                store.toggle()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(store.isActive ? .secondary : .accentColor)
                        }

                        Divider()

                        Toggle("仅翻转外接鼠标滚轮（保留触控板自然滚动）", isOn: $store.mouseOnly)
                            .toggleStyle(.switch)

                        Toggle("翻转垂直滚轮（上下滚动）", isOn: $store.reverseVertical)
                            .toggleStyle(.switch)

                        Toggle("翻转水平滚轮（左右倾斜 / 侧滚轮）", isOn: $store.reverseHorizontal)
                            .toggleStyle(.switch)
                    }
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

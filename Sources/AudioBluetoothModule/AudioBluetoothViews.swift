import SwiftUI
import CoreKit

public struct AudioBluetoothPopoverView: View {
    @ObservedObject public var store: AudioBluetoothStore
    public let onBack: () -> Void

    public init(store: AudioBluetoothStore, onBack: @escaping () -> Void) {
        self.store = store
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubpageHeader(title: "蓝牙与音频", onBack: onBack) {
                if store.isRefreshingBluetooth {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)
                } else {
                    Button {
                        store.refreshAudioDevices()
                        store.refreshBluetoothDevices(force: true)
                    } label: {
                        GlassNeutralCircle(size: 24) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("刷新蓝牙与音频设备")
                }
            }

            // 1. AirPods / Bluetooth Hero Card (Triple Battery Rings for AirPods)
            if let primaryBT = store.bluetoothDevices.first(where: { $0.isAudioDevice }) ?? store.bluetoothDevices.first {
                VStack(spacing: 10) {
                    HStack(spacing: 9) {
                        ZStack {
                            if primaryBT.isConnected {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 28, height: 28)
                            } else {
                                GlassNeutralCircle(size: 28) { EmptyView() }
                            }
                            if store.busyDeviceAddress == primaryBT.address {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: primaryBT.symbolName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(primaryBT.isConnected ? Color.white : Color.primary)
                            }
                        }

                        Text(primaryBT.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Button {
                            store.toggleBluetoothConnection(primaryBT)
                        } label: {
                            Text(primaryBT.isConnected ? "断开" : "连接")
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3.5)
                                .background(
                                    Capsule().fill(primaryBT.isConnected ? Color.primary.opacity(0.11) : Color.accentColor)
                                )
                                .foregroundStyle(primaryBT.isConnected ? Color.primary : Color.white)
                        }
                        .buttonStyle(.plain)
                    }

                    if primaryBT.leftBattery != nil || primaryBT.rightBattery != nil || primaryBT.caseBattery != nil {
                        HStack(spacing: 12) {
                            if let l = primaryBT.leftBattery {
                                MiniBatteryRingCell(title: "左耳 L", percent: l)
                            }
                            if let r = primaryBT.rightBattery {
                                MiniBatteryRingCell(title: "右耳 R", percent: r)
                            }
                            if let c = primaryBT.caseBattery {
                                MiniBatteryRingCell(title: "充电盒", percent: c)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    } else if let m = primaryBT.mainBattery {
                        HStack {
                            Text("设备电量")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(m)%")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                    }

                    let others = store.bluetoothDevices.filter { $0.id != primaryBT.id }
                    if !others.isEmpty {
                        Divider().opacity(0.45)
                        VStack(spacing: 3) {
                            ForEach(others.prefix(2)) { dev in
                                BluetoothDeviceRow(
                                    device: dev,
                                    isBusy: store.busyDeviceAddress == dev.address
                                ) {
                                    store.toggleBluetoothConnection(dev)
                                }
                            }
                        }
                    }
                }
                .padding(11)
                .glassBentoCard(cornerRadius: 18)
            }

            // 2. Tactile Control Center Volume Scrubber
            TactileVolumeBar(
                volume: store.outputVolume,
                isMuted: store.isMuted,
                onVolumeChange: { store.setOutputVolume($0) },
                onToggleMute: { store.setOutputMute(!store.isMuted) }
            )

            // 3. Audio Output & Input Routing Card
            VStack(alignment: .leading, spacing: 4) {
                Text("音频输出")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)

                VStack(spacing: 2) {
                    ForEach(store.outputDevices.prefix(5)) { dev in
                        AudioOutputRow(device: dev) {
                            store.selectOutputDevice(dev)
                        }
                    }
                }

                if !store.inputDevices.isEmpty {
                    Divider().opacity(0.45).padding(.vertical, 3)

                    HStack(spacing: 6) {
                        Text("音频输入（麦克风）")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let currentIn = store.currentInputDevice, !currentIn.isBuiltin, store.builtinInputDevice != nil {
                            Button("锁定内建麦") {
                                store.switchToBuiltinMic()
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.11)))
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)

                    VStack(spacing: 2) {
                        ForEach(store.inputDevices.prefix(4)) { dev in
                            AudioOutputRow(device: dev) {
                                store.selectInputDevice(dev)
                            }
                        }
                    }
                }
            }
            .padding(9)
            .glassBentoCard(cornerRadius: 16)

            if let msg = store.statusMessage {
                Text(msg)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            HStack {
                Button("蓝牙设置…") {
                    store.openBluetoothSettings()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("声音设置…") {
                    store.openSoundSettings()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .onAppear {
            store.refreshAudioDevices()
            store.refreshBluetoothDevices()
        }
    }
}

private struct MiniBatteryRingCell: View {
    let title: String
    let percent: Int

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                CircularProgressRing(
                    progress: Double(percent) / 100.0,
                    lineWidth: 3.3,
                    color: percent <= 20 ? .red : .green
                )
                .frame(width: 40, height: 40)

                Text("\(percent)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
            }
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BluetoothDeviceRow: View {
    let device: BluetoothDeviceInfo
    let isBusy: Bool
    let onTap: () -> Void
    @StateObject private var hover = HoverTracker()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(device.isConnected ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(width: 26, height: 26)
                    if isBusy {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: device.symbolName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(device.isConnected ? .white : .primary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 12, weight: device.isConnected ? .semibold : .regular))
                        .lineLimit(1)

                    if device.hasAnyBattery {
                        HStack(spacing: 6) {
                            if let l = device.leftBattery {
                                Text("L \(l)%")
                            }
                            if let r = device.rightBattery {
                                Text("R \(r)%")
                            }
                            if let c = device.caseBattery {
                                Text("盒 \(c)%")
                            }
                            if device.leftBattery == nil && device.rightBattery == nil, let m = device.mainBattery {
                                Text("电量 \(m)%")
                            }
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    } else {
                        Text(device.isConnected ? "已连接" : "未连接")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                Text(device.isConnected ? "断开" : "连接")
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill(device.isConnected ? Color.primary.opacity(0.10) : Color.accentColor.opacity(0.16))
                    )
                    .foregroundStyle(device.isConnected ? Color.secondary : Color.accentColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowStyle(hover: hover, cornerRadius: 10))
    }
}

private struct AudioOutputRow: View {
    let device: AudioDeviceInfo
    let onTap: () -> Void
    @StateObject private var hover = HoverTracker()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(device.isCurrentDefault ? Color.accentColor : .secondary)
                    .frame(width: 18)

                Text(device.name)
                    .font(.system(size: 12, weight: device.isCurrentDefault ? .semibold : .regular))
                    .lineLimit(1)

                Spacer()

                if device.isCurrentDefault {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowStyle(hover: hover, cornerRadius: 9))
    }
}

public struct AudioBluetoothConsoleView: View {
    @ObservedObject public var store: AudioBluetoothStore
    @ObservedObject public var moduleSettings: ModuleSettings

    public init(store: AudioBluetoothStore, moduleSettings: ModuleSettings) {
        self.store = store
        self.moduleSettings = moduleSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text("原生读取 AirPods 左右耳与充电盒真实电量，支持一键连接/断开、音频路由切换及切回内建麦防通话降质。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("在菜单栏显示", isOn: $moduleSettings.audioBluetoothEnabled)
                        .toggleStyle(.switch)
                }

                if let msg = store.statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(msg)
                            .font(.callout)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }

                GroupBox("AirPods 与蓝牙外设") {
                    VStack(spacing: 6) {
                        if store.bluetoothDevices.isEmpty {
                            Text("暂未发现配对的蓝牙音频或外设")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        } else {
                            ForEach(store.bluetoothDevices) { dev in
                                BluetoothDeviceRow(device: dev, isBusy: store.busyDeviceAddress == dev.address) {
                                    store.toggleBluetoothConnection(dev)
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                GroupBox("音频输入 / 输出设备") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("输出设备")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(store.outputDevices) { dev in
                            AudioOutputRow(device: dev) {
                                store.selectOutputDevice(dev)
                            }
                        }

                        Divider()

                        HStack {
                            Text("输入设备（麦克风）")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let cur = store.currentInputDevice, !cur.isBuiltin, store.builtinInputDevice != nil {
                                Button("切回 Mac 内建麦克风（保高清音质）") {
                                    store.switchToBuiltinMic()
                                }
                                .controlSize(.small)
                            }
                        }
                        ForEach(store.inputDevices) { dev in
                            AudioOutputRow(device: dev) {
                                store.selectInputDevice(dev)
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .onAppear {
            store.refreshAudioDevices()
            store.refreshBluetoothDevices()
        }
    }
}

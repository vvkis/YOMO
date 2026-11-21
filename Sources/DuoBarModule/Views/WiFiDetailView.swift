import SwiftUI
import CoreKit

struct WiFiDetailView: View {
    @ObservedObject var store: DuoBarStore
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubpageHeader(title: "Wi-Fi", onBack: onBack) {
                Toggle("", isOn: Binding(
                    get: { store.wifi.isPoweredOn },
                    set: { store.setWiFiPower($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if !store.wifi.isPoweredOn {
                VStack(spacing: 8) {
                    GlassNeutralCircle(size: 44) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("Wi-Fi 已关闭")
                        .font(.system(size: 13, weight: .semibold))
                    Text("打开右上角开关以恢复无线网络连接")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .glassBentoCard(cornerRadius: 16)
            } else {
                // Hero Connection Card
                HStack(spacing: 10) {
                    ZStack {
                        if store.wifi.isConnected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 34, height: 34)
                        } else {
                            GlassNeutralCircle(size: 34) { EmptyView() }
                        }
                        Image(systemName: "wifi")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(store.wifi.isConnected ? Color.white : Color.secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(heroTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        if store.wifi.isConnected {
                            HStack(spacing: 6) {
                                if let band = store.wifi.channelBandLabel {
                                    Text(band)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1)
                                        .background(Color.primary.opacity(0.10), in: Capsule())
                                }
                                if store.wifi.rssi != 0 {
                                    Text("\(store.wifi.rssi) dBm")
                                }
                                if store.wifi.transmitRateMbps > 0 {
                                    Text("· \(Int(round(store.wifi.transmitRateMbps))) Mbps")
                                }
                            }
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        } else {
                            Text("请选择下方网络进行连接")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(10)
                .glassBentoCard(cornerRadius: 16)

                // Location permission hint if macOS redacts SSID
                if store.wifi.isConnected && store.wifi.currentSSID == nil {
                    HStack(spacing: 6) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text("开启定位权限以识别当前 Wi-Fi 名称")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("授权") {
                            store.requestLocationForSSID()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassBentoCard(cornerRadius: 13)
                }

                // Known Nearby Networks Elevated Bento Card (in-range only)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("附近已知网络")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if store.wifi.isScanning {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Button {
                                store.scanNearbyWiFi()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("重新扫描附近网络")
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            if store.wifi.knownNetworks.isEmpty {
                                Text(store.wifi.isScanning
                                     ? "正在扫描附近的已知网络…"
                                     : (store.wifi.locationAuthorized ? "附近暂无已保存的网络" : "需授权定位权限以扫描附近的已知网络"))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 6)
                            } else {
                                ForEach(store.wifi.knownNetworks) { net in
                                    let isActive = (net.ssid == store.wifi.currentSSID)
                                    let isConnecting = (net.ssid == store.wifi.connectingSSID)
                                    WiFiNetworkRow(
                                        ssid: net.ssid,
                                        isActive: isActive,
                                        isSecured: net.isSecured,
                                        isConnecting: isConnecting,
                                        badgeText: isActive ? "已连接" : net.channelBand
                                    ) {
                                        if !isActive {
                                            store.connectKnownWiFi(ssid: net.ssid)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .padding(8)
                .glassBentoCard(cornerRadius: 16)

                // Collapsible Other Networks Card
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.showOtherNetworks.toggle()
                        }
                        if store.showOtherNetworks && store.wifi.nearbyNetworks.isEmpty && !store.wifi.isScanning {
                            store.scanNearbyWiFi()
                        }
                    } label: {
                        HStack {
                            Text("其他网络")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if store.wifi.isScanning {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.75)
                            }
                            Image(systemName: store.showOtherNetworks ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if store.showOtherNetworks {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 2) {
                                if store.wifi.isScanning && store.wifi.nearbyNetworks.isEmpty {
                                    Text("正在扫描附近网络…")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                } else if store.wifi.nearbyNetworks.isEmpty {
                                    Text(store.wifi.locationAuthorized ? "未发现其他附近网络" : "需授权定位后方可扫描附近网络名称")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                } else {
                                    ForEach(store.wifi.nearbyNetworks) { net in
                                        WiFiNetworkRow(
                                            ssid: net.ssid,
                                            isActive: false,
                                            isSecured: net.isSecured,
                                            isConnecting: store.wifi.connectingSSID == net.ssid,
                                            badgeText: net.channelBand
                                        ) {
                                            if net.isSecured {
                                                store.passwordTargetSSID = net.ssid
                                                store.passwordInput = ""
                                            } else {
                                                store.connectNearbyWiFi(ssid: net.ssid, password: nil)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 108)

                        if let target = store.passwordTargetSSID {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("输入「\(target)」密码")
                                    .font(.system(size: 11, weight: .medium))
                                HStack(spacing: 6) {
                                    SecureField("Wi-Fi 密码", text: $store.passwordInput)
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                    Button("连接") {
                                        let pwd = store.passwordInput
                                        store.passwordTargetSSID = nil
                                        store.passwordInput = ""
                                        store.connectNearbyWiFi(ssid: target, password: pwd)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    Button("取消") {
                                        store.passwordTargetSSID = nil
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(8)
                            .glassBentoCard(cornerRadius: 11)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .glassBentoCard(cornerRadius: 14)

                if let err = store.wifi.lastError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
            }

            HStack {
                Spacer()
                Button("Wi-Fi 设置…") {
                    store.openWiFiSettings()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .onAppear {
            store.scanNearbyWiFi()
        }
    }

    private var heroTitle: String {
        if !store.wifi.isConnected { return "未连接网络" }
        return store.wifi.currentSSID ?? "已连接 Wi-Fi"
    }
}

private struct WiFiNetworkRow: View {
    let ssid: String
    let isActive: Bool
    let isSecured: Bool
    let isConnecting: Bool
    let badgeText: String?
    let onTap: () -> Void

    @StateObject private var hover = HoverTracker()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack {
                    if isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 24, height: 24)
                    } else {
                        GlassNeutralCircle(size: 24) { EmptyView() }
                    }
                    if isConnecting {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "wifi")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isActive ? Color.white : Color.primary)
                    }
                }

                Text(ssid)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if isSecured {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowStyle(hover: hover, cornerRadius: 10))
    }
}

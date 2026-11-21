import Foundation
import AppKit
import CoreWLAN
import CoreLocation

final class WiFiService: NSObject, CLLocationManagerDelegate, CWEventDelegate, @unchecked Sendable {
    private let client = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private let cacheLock = NSLock()
    private var cachedScanNetworks: [CWNetwork] = []

    var onAuthorizationChanged: (@Sendable () -> Void)?
    var onWiFiEventChanged: (@Sendable () -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        client.delegate = self
        for type: CWEventType in [.powerDidChange, .ssidDidChange, .linkDidChange] {
            try? client.startMonitoringEvent(with: type)
        }
    }

    deinit {
        try? client.stopMonitoringAllEvents()
    }

    var isLocationAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedAlways || status == .authorized
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChanged?()
    }

    // MARK: - CWEventDelegate (System Event-Driven Push)

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        onWiFiEventChanged?()
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        onWiFiEventChanged?()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        onWiFiEventChanged?()
    }

    func sampleQuickState(previous: WiFiState) -> WiFiState {
        var state = previous
        state.locationAuthorized = isLocationAuthorized

        guard let iface = client.interface() else {
            state.interfaceName = ""
            state.isPoweredOn = false
            state.isConnected = false
            state.currentSSID = nil
            state.rssi = 0
            state.transmitRateMbps = 0
            state.channelBandLabel = nil
            return state
        }

        state.interfaceName = iface.interfaceName ?? ""
        let powered = iface.powerOn()
        state.isPoweredOn = powered

        if !powered {
            state.isConnected = false
            state.currentSSID = nil
            state.rssi = 0
            state.transmitRateMbps = 0
            state.channelBandLabel = nil
            return state
        }

        let rssi = iface.rssiValue()
        let txRate = iface.transmitRate()
        let ssid = iface.ssid()

        state.rssi = rssi
        state.transmitRateMbps = txRate
        state.currentSSID = ssid
        let band = iface.wlanChannel()?.channelBand
        state.channelBandLabel = Self.fullBandLabel(band)
        state.isConnected = (ssid != nil) || (rssi != 0 && txRate > 0) || iface.serviceActive()

        if let ssid, state.knownNetworks.isEmpty {
            state.knownNetworks = [
                WiFiNetworkItem(
                    ssid: ssid,
                    isKnown: true,
                    isSecured: true,
                    rssi: rssi != 0 ? rssi : nil,
                    channelBand: Self.shortBand(band)
                )
            ]
        }

        return state
    }

    /// Scans live nearby Wi-Fi beacons once and classifies them using CoreWLAN's native `CWConfiguration.networkProfiles`:
    /// - `knownNearby`: saved network profiles that are actually in range right now (plus `currentSSID`)
    /// - `otherNearby`: unsaved networks currently in range
    func scanAndClassifyNetworks(
        currentSSID: String?,
        currentRSSI: Int,
        completion: @escaping @Sendable (_ knownNearby: [WiFiNetworkItem], _ otherNearby: [WiFiNetworkItem], _ error: String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let iface = self.client.interface(), iface.powerOn() else {
                DispatchQueue.main.async { completion([], [], nil) }
                return
            }

            // 1. Read saved/preferred SSID list directly from CoreWLAN CWConfiguration (zero subprocess)
            var preferredSet = Set<String>()
            if let profiles = iface.configuration()?.networkProfiles {
                for case let profile as CWNetworkProfile in profiles {
                    if let s = profile.ssid, !s.isEmpty {
                        preferredSet.insert(s)
                    }
                }
            }

            let curBandShort = Self.shortBand(iface.wlanChannel()?.channelBand)

            // 2. Perform live hardware scan to see which networks are actually nearby
            do {
                let scanned = try iface.scanForNetworks(withName: nil)
                self.cacheLock.lock()
                self.cachedScanNetworks = Array(scanned)
                self.cacheLock.unlock()

                var bestBySSID: [String: CWNetwork] = [:]
                for net in scanned {
                    guard let ssid = net.ssid, !ssid.isEmpty else { continue }
                    if let existing = bestBySSID[ssid] {
                        if net.rssiValue > existing.rssiValue {
                            bestBySSID[ssid] = net
                        }
                    } else {
                        bestBySSID[ssid] = net
                    }
                }

                // 3. Filter known networks strictly to those detected nearby (or currently connected)
                var knownItems: [WiFiNetworkItem] = []
                var seenKnown = Set<String>()

                for (ssid, net) in bestBySSID where preferredSet.contains(ssid) || ssid == currentSSID {
                    seenKnown.insert(ssid)
                    knownItems.append(WiFiNetworkItem(
                        ssid: ssid,
                        isKnown: true,
                        isSecured: !net.supportsSecurity(.none),
                        rssi: net.rssiValue,
                        channelBand: Self.shortBand(net.wlanChannel?.channelBand)
                    ))
                }

                // Always preserve currently connected network even if its beacon wasn't in this scan window
                if let cur = currentSSID, !cur.isEmpty, !seenKnown.contains(cur) {
                    knownItems.append(WiFiNetworkItem(
                        ssid: cur,
                        isKnown: true,
                        isSecured: true,
                        rssi: currentRSSI != 0 ? currentRSSI : nil,
                        channelBand: curBandShort
                    ))
                }

                knownItems.sort { a, b in
                    if a.ssid == currentSSID { return true }
                    if b.ssid == currentSSID { return false }
                    return (a.rssi ?? -999) > (b.rssi ?? -999)
                }

                // 4. Remaining live nearby networks go to "其他网络"
                let otherItems: [WiFiNetworkItem] = bestBySSID.values
                    .filter { net in
                        guard let s = net.ssid else { return false }
                        return !preferredSet.contains(s) && s != currentSSID
                    }
                    .sorted { $0.rssiValue > $1.rssiValue }
                    .prefix(12)
                    .map { net in
                        WiFiNetworkItem(
                            ssid: net.ssid ?? "",
                            isKnown: false,
                            isSecured: !net.supportsSecurity(.none),
                            rssi: net.rssiValue,
                            channelBand: Self.shortBand(net.wlanChannel?.channelBand)
                        )
                    }

                DispatchQueue.main.async {
                    completion(knownItems, otherItems, nil)
                }
            } catch {
                var fallback: [WiFiNetworkItem] = []
                if let cur = currentSSID, !cur.isEmpty {
                    fallback.append(WiFiNetworkItem(
                        ssid: cur,
                        isKnown: true,
                        isSecured: true,
                        rssi: currentRSSI != 0 ? currentRSSI : nil,
                        channelBand: curBandShort
                    ))
                }
                DispatchQueue.main.async {
                    completion(fallback, [], "扫描附近网络失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func setPower(_ on: Bool, interfaceName: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let iface = self?.client.interface() {
                do {
                    try iface.setPower(on)
                    DispatchQueue.main.async { completion(true, nil) }
                    return
                } catch {
                    // Fallback to networksetup only for power toggle (no sensitive credentials)
                }
            }
            let targetIface = !interfaceName.isEmpty ? interfaceName : (self?.client.interface()?.interfaceName ?? "")
            guard !targetIface.isEmpty else {
                DispatchQueue.main.async { completion(false, "未找到可用的 Wi-Fi 接口") }
                return
            }
            let arg = on ? "on" : "off"
            let out = Self.runCommand("/usr/sbin/networksetup", args: ["-setairportpower", targetIface, arg])
            let ok = !out.lowercased().contains("error")
            DispatchQueue.main.async {
                completion(ok, ok ? nil : out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    func connectToKnownNetwork(ssid: String, interfaceName: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let targetIface = !interfaceName.isEmpty ? interfaceName : (self?.client.interface()?.interfaceName ?? "")
            guard !targetIface.isEmpty else {
                DispatchQueue.main.async { completion(false, "未找到可用的 Wi-Fi 接口") }
                return
            }
            // Known network credentials are retrieved by macOS from System Keychain
            let out = Self.runCommand("/usr/sbin/networksetup", args: ["-setairportnetwork", targetIface, ssid])
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = trimmed.isEmpty
            DispatchQueue.main.async {
                completion(ok, ok ? nil : trimmed)
            }
        }
    }

    func connectToNearbyNetwork(ssid: String, password: String?, completion: @escaping @Sendable (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let iface = self.client.interface() else {
                DispatchQueue.main.async { completion(false, "未找到可用的 Wi-Fi 接口") }
                return
            }

            self.cacheLock.lock()
            var targetNetwork = self.cachedScanNetworks
                .filter { $0.ssid == ssid }
                .max(by: { $0.rssiValue < $1.rssiValue })
            self.cacheLock.unlock()

            if targetNetwork == nil {
                targetNetwork = (try? iface.scanForNetworks(withName: ssid))?.max(by: { $0.rssiValue < $1.rssiValue })
            }

            guard let matched = targetNetwork else {
                DispatchQueue.main.async {
                    completion(false, "未在附近找到「\(ssid)」")
                }
                return
            }

            do {
                try iface.associate(to: matched, password: password)
                DispatchQueue.main.async { completion(true, nil) }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "连接「\(ssid)」失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func fullBandLabel(_ band: CWChannelBand?) -> String? {
        switch band {
        case .band6GHz: return "6 GHz"
        case .band5GHz: return "5 GHz"
        case .band2GHz: return "2.4 GHz"
        default: return nil
        }
    }

    private static func shortBand(_ band: CWChannelBand?) -> String? {
        switch band {
        case .band6GHz: return "6G"
        case .band5GHz: return "5G"
        case .band2GHz: return "2.4G"
        default: return nil
        }
    }

    private static func runCommand(_ path: String, args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

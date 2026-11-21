import Foundation
import AppKit
import SwiftUI
import CoreKit

public enum BadgeStyle: String, CaseIterable, Identifiable {
    case capsule = "D"     // 圆环 + 微胶囊直读 (默认)
    case dualRing = "A"    // 同心双环 + 内存数值
    case triArc = "B"      // 三段仪表环 + Wi-Fi
    case splitArc = "C"    // 左右双弧 + Wi-Fi

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .capsule: return "D. 圆环 + 微胶囊"
        case .dualRing: return "A. 双环 + 内存"
        case .triArc: return "B. 三段环 + Wi-Fi"
        case .splitArc: return "C. 左右弧 + Wi-Fi"
        }
    }
}

public enum TelemetrySortTab: String, CaseIterable, Identifiable {
    case cpu = "CPU 占用"
    case memory = "内存占用"

    public var id: String { rawValue }
}

public struct ProcessStatItem: Identifiable, @unchecked Sendable {
    public let id: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let icon: NSImage?

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64, icon: NSImage?) {
        self.id = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.icon = icon
    }

    public var formattedMemory: String {
        let mb = Double(memoryBytes) / 1_048_576.0
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }

    public var formattedCPU: String {
        String(format: "%.1f%%", cpuPercent)
    }
}

public struct CPUStats: Sendable {
    public var totalUsage: Double = 0
    public var userUsage: Double = 0
    public var systemUsage: Double = 0
    public var loadAverage: String = "0.00"
    public var history: [Double] = Array(repeating: 0, count: 24)
    public init(
        totalUsage: Double = 0,
        userUsage: Double = 0,
        systemUsage: Double = 0,
        loadAverage: String = "0.00",
        history: [Double] = Array(repeating: 0, count: 24)
    ) {
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.loadAverage = loadAverage
        self.history = history
    }
}

public struct MemoryStats: Sendable {
    public var usagePercent: Double = 0
    public var usedGB: Double = 0
    public var totalGB: Double = 0
    public var activeGB: Double = 0
    public var wiredGB: Double = 0
    public var compressedGB: Double = 0
    public var pressureLevel: Pressure = .normal

    public enum Pressure: String, Sendable {
        case normal = "正常"
        case warning = "偏高"
        case critical = "紧张"
    }

    public init(
        usagePercent: Double = 0,
        usedGB: Double = 0,
        totalGB: Double = 0,
        activeGB: Double = 0,
        wiredGB: Double = 0,
        compressedGB: Double = 0,
        pressureLevel: Pressure = .normal
    ) {
        self.usagePercent = usagePercent
        self.usedGB = usedGB
        self.totalGB = totalGB
        self.activeGB = activeGB
        self.wiredGB = wiredGB
        self.compressedGB = compressedGB
        self.pressureLevel = pressureLevel
    }
}

public struct DiskStats: Sendable {
    public var usagePercent: Double = 0
    public var usedGB: Double = 0
    public var totalGB: Double = 0
    public var availableGB: Double = 0

    public init(
        usagePercent: Double = 0,
        usedGB: Double = 0,
        totalGB: Double = 0,
        availableGB: Double = 0
    ) {
        self.usagePercent = usagePercent
        self.usedGB = usedGB
        self.totalGB = totalGB
        self.availableGB = availableGB
    }
}

public struct NetworkStats: Sendable {
    public var uploadBytesPerSec: Double = 0
    public var downloadBytesPerSec: Double = 0
    public var localIP: String = "--"
    public var isConnected: Bool = false
    public var activeInterface: String = ""

    public init(
        uploadBytesPerSec: Double = 0,
        downloadBytesPerSec: Double = 0,
        localIP: String = "--",
        isConnected: Bool = false,
        activeInterface: String = ""
    ) {
        self.uploadBytesPerSec = uploadBytesPerSec
        self.downloadBytesPerSec = downloadBytesPerSec
        self.localIP = localIP
        self.isConnected = isConnected
        self.activeInterface = activeInterface
    }

    public var dominantIsUpload: Bool {
        uploadBytesPerSec > max(10_240, downloadBytesPerSec * 2.0)
    }

    public var dominantSpeedBytesPerSec: Double {
        dominantIsUpload ? uploadBytesPerSec : downloadBytesPerSec
    }

    public var dominantSpeedBucket: String {
        "\(dominantIsUpload ? "U" : "D"):\(Formatters.compactSpeed(dominantSpeedBytesPerSec))"
    }
}

public struct BatteryStats: Sendable {
    public var hasBattery: Bool = true
    public var percentage: Int = 100
    public var isCharging: Bool = false
    public var isCharged: Bool = false
    public var isPluggedIn: Bool = false
    public var isLowPowerMode: Bool = false
    public var timeRemainingText: String = "计算中…"
    public var healthPercent: Int = 100
    public var cycleCount: Int = 0
    public var systemLoadWatts: Double? = nil
    public var systemPowerInWatts: Double? = nil
    public var adapterRatedWatts: Int? = nil

    public var powerSourceLabel: String {
        if let watts = adapterRatedWatts, isPluggedIn {
            return isCharging ? "\(watts)W 适配器（充电中）" : "\(watts)W 适配器"
        }
        if isCharging { return "电源适配器（充电中）" }
        if isPluggedIn { return "电源适配器" }
        return "电池"
    }

    public var ringColor: Color {
        if isLowPowerMode { return .orange }
        if percentage <= 20 && !isCharging { return .red }
        return .green
    }

    public init() {}
}

public struct WiFiNetworkItem: Identifiable, Hashable, Sendable {
    public var id: String { ssid }
    public let ssid: String
    public let isKnown: Bool
    public let isSecured: Bool
    public let rssi: Int?
    public let channelBand: String?

    public init(ssid: String, isKnown: Bool, isSecured: Bool, rssi: Int?, channelBand: String?) {
        self.ssid = ssid
        self.isKnown = isKnown
        self.isSecured = isSecured
        self.rssi = rssi
        self.channelBand = channelBand
    }
}

public struct WiFiState: Sendable {
    public var interfaceName: String = ""
    public var isPoweredOn: Bool = true
    public var currentSSID: String? = nil
    public var rssi: Int = 0
    public var transmitRateMbps: Double = 0
    public var channelBandLabel: String? = nil
    public var isConnected: Bool = false
    public var knownNetworks: [WiFiNetworkItem] = []
    public var nearbyNetworks: [WiFiNetworkItem] = []
    public var isScanning: Bool = false
    public var connectingSSID: String? = nil
    public var lastError: String? = nil
    public var locationAuthorized: Bool = false

    public var signalBars: Int {
        guard isPoweredOn && isConnected else { return 0 }
        if rssi == 0 { return 3 }
        if rssi >= -60 { return 3 }
        if rssi >= -75 { return 2 }
        return 1
    }
    public init() {}
}

public final class AppPreferences: ObservableObject {
    @AppStorage("badgeStyle") public var badgeStyleRaw: String = BadgeStyle.capsule.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("semanticColor") public var semanticColor: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("refreshInterval") public var refreshInterval: Double = 2.0 {
        willSet { objectWillChange.send() }
    }

    public init() {}

    public var badgeStyle: BadgeStyle {
        get { BadgeStyle(rawValue: badgeStyleRaw) ?? .capsule }
        set {
            badgeStyleRaw = newValue.rawValue
        }
    }
}

import Foundation
import AppKit
import IOKit
import IOKit.ps

final class BatteryService: @unchecked Sendable {
    var onPowerSourceChanged: (@Sendable () -> Void)?
    private var runLoopSource: CFRunLoopSource?
    private var lpmObserver: NSObjectProtocol?

    init() {
        setupNotifications()
    }

    deinit {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        if let lpmObserver {
            NotificationCenter.default.removeObserver(lpmObserver)
        }
    }

    private func setupNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            service.onPowerSourceChanged?()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = source
        }

        lpmObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onPowerSourceChanged?()
        }
    }

    /// Samples battery state. When `includeDetailedIORegistry` is false (e.g. while the popover is closed),
    /// only reads the lightweight IOPS power source summary required for the menu bar badge,
    /// skipping the heavy `AppleSmartBattery` IORegistry dictionary dump.
    func sampleBattery(includeDetailedIORegistry: Bool = true, previous: BatteryStats? = nil) -> BatteryStats {
        var stats = previous ?? BatteryStats()
        stats.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // 1. High-level IOPS power source info (lightweight, always fast)
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] {

            stats.hasBattery = true
            let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
            let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
            if maxCap > 0 {
                stats.percentage = min(100, max(0, Int(round((Double(current) / Double(maxCap)) * 100.0))))
            }

            let source = desc[kIOPSPowerSourceStateKey as String] as? String ?? ""
            stats.isPluggedIn = (source == kIOPSACPowerValue as String)
            stats.isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            stats.isCharged = (desc[kIOPSIsChargedKey as String] as? Bool) ?? false

            let rawTimeToEmpty = (desc[kIOPSTimeToEmptyKey as String] as? NSNumber)?.intValue ?? -1
            let rawTimeToFull = (desc[kIOPSTimeToFullChargeKey as String] as? NSNumber)?.intValue ?? -1

            var resolvedTimeToEmpty = validMinutes(rawTimeToEmpty)
            if resolvedTimeToEmpty == nil && !stats.isPluggedIn && !stats.isCharging {
                let estSeconds = IOPSGetTimeRemainingEstimate()
                if estSeconds > 0 && estSeconds.isFinite {
                    resolvedTimeToEmpty = validMinutes(Int(round(estSeconds / 60.0)))
                }
            }
            let resolvedTimeToFull = validMinutes(rawTimeToFull)

            if stats.isCharging {
                if let mins = resolvedTimeToFull {
                    stats.timeRemainingText = "充满约 \(formatMinutes(mins))"
                } else {
                    stats.timeRemainingText = "正在充电"
                }
            } else if stats.isPluggedIn {
                stats.timeRemainingText = stats.isCharged ? "已充满" : "已接通电源"
            } else {
                if let mins = resolvedTimeToEmpty {
                    stats.timeRemainingText = "剩余约 \(formatMinutes(mins))"
                } else {
                    stats.timeRemainingText = stats.percentage >= 100 ? "使用电池" : "计算续航中…"
                }
            }
        } else {
            stats.hasBattery = false
            stats.percentage = 100
            stats.isPluggedIn = true
            stats.isCharged = true
            stats.timeRemainingText = "电源供电"
        }

        guard includeDetailedIORegistry else {
            return stats
        }

        // 2. Detailed IORegistry AppleSmartBattery info (cycles, health, wattage — sampled only when UI is open)
        stats.systemLoadWatts = nil
        stats.systemPowerInWatts = nil
        stats.adapterRatedWatts = nil

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propsRef?.takeRetainedValue() as? [String: Any] {

                let batteryData = dict["BatteryData"] as? [String: Any]

                if let cycles = (dict["CycleCount"] as? NSNumber)?.intValue {
                    stats.cycleCount = cycles
                }

                // Match macOS System Settings ("Maximum Capacity"): prefer NominalChargeCapacity / DesignCapacity
                // before falling back to AppleRawMaxCapacity (which fluctuates with temperature & battery management).
                let designCap = numericDouble(dict["DesignCapacity"])
                    ?? numericDouble(batteryData?["DesignCapacity"])
                    ?? 0
                let nominalMaxCap = numericDouble(dict["NominalChargeCapacity"])
                    ?? numericDouble(batteryData?["NominalChargeCapacity"])
                    ?? numericDouble(dict["AppleRawMaxCapacity"])
                    ?? numericDouble(batteryData?["AppleRawMaxCapacity"])
                    ?? 0

                if designCap > 0 && nominalMaxCap > 0 {
                    stats.healthPercent = min(100, max(1, Int(round((nominalMaxCap / designCap) * 100.0))))
                }

                // Hardware SMBus time-remaining fallback when IOPS has not published an estimate yet
                if stats.isCharging && stats.timeRemainingText == "正在充电" {
                    if let mins = validMinutes(dict["AvgTimeToFull"]) ?? validMinutes(batteryData?["AvgTimeToFull"]) {
                        stats.timeRemainingText = "充满约 \(formatMinutes(mins))"
                    }
                } else if !stats.isPluggedIn && !stats.isCharging && !stats.timeRemainingText.hasPrefix("剩余约") {
                    if let mins = validMinutes(dict["AvgTimeToEmpty"])
                        ?? validMinutes(dict["TimeRemaining"])
                        ?? validMinutes(batteryData?["AvgTimeToEmpty"]) {
                        stats.timeRemainingText = "剩余约 \(formatMinutes(mins))"
                    }
                }

                if stats.isPluggedIn,
                   let adapter = dict["AdapterDetails"] as? [String: Any],
                   let ratedW = adapter["Watts"] as? Int,
                   ratedW > 0 {
                    stats.adapterRatedWatts = ratedW
                }

                if let telemetry = dict["PowerTelemetryData"] as? [String: Any] {
                    if let sysLoadNum = telemetry["SystemLoad"] as? NSNumber {
                        let mw = sysLoadNum.int64Value
                        if mw > 0 {
                            stats.systemLoadWatts = Double(mw) / 1000.0
                        }
                    }
                    if stats.isPluggedIn, let sysInNum = telemetry["SystemPowerIn"] as? NSNumber {
                        let mw = sysInNum.int64Value
                        if mw > 0 {
                            stats.systemPowerInWatts = Double(mw) / 1000.0
                        }
                    }
                }
            }
        }

        return stats
    }

    func setLowPowerMode(enabled: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        let target = enabled ? "1" : "0"
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptSource = "do shell script \"/usr/bin/pmset -a lowpowermode \(target)\" with administrator privileges"
            var errorInfo: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                _ = script.executeAndReturnError(&errorInfo)
                let ok = (errorInfo == nil)
                DispatchQueue.main.async {
                    completion(ok)
                }
            } else {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

    func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func numericDouble(_ value: Any?) -> Double? {
        if let n = value as? NSNumber {
            return n.doubleValue
        }
        return nil
    }

    /// Accepts only genuine SMBus/IOPS minute counts (1 ... 65534), rejecting -1, 0, and 0xFFFF sentinel.
    private func validMinutes(_ value: Any?) -> Int? {
        guard let mins = (value as? NSNumber)?.intValue, mins > 0, mins < 65535 else {
            return nil
        }
        return mins
    }

    private func formatMinutes(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}

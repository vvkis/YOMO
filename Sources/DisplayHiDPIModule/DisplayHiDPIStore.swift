import Foundation
import AppKit
import CoreGraphics
import ObjectiveC

public enum DisplayModeFilter: String, CaseIterable, Identifiable {
    case hiDPIOnly = "仅 HiDPI"
    case all = "包含普通模式"

    public var id: String { rawValue }
}

public struct DisplayModeOption: Identifiable, Hashable {
    public let id: String
    public let modeNumber: Int32
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Int
    public let isHiDPI: Bool
    public let isDefault: Bool
    public let isNative: Bool
    public let isCurrent: Bool
    public let cgModeIndex: Int?

    public var resolutionText: String { "\(width) × \(height)" }
    public var pixelText: String { "\(pixelWidth) × \(pixelHeight)" }

    public var aspectRatioLabel: String {
        guard width > 0, height > 0 else { return "" }
        let ratio = Double(width) / Double(height)
        if abs(ratio - 16.0 / 9.0) < 0.02 { return "16:9" }
        if abs(ratio - 16.0 / 10.0) < 0.025 { return "16:10" }
        if abs(ratio - 21.0 / 9.0) < 0.06 { return "21:9" }
        if abs(ratio - 32.0 / 9.0) < 0.08 { return "32:9" }
        if abs(ratio - 4.0 / 3.0) < 0.025 { return "4:3" }
        if abs(ratio - 5.0 / 4.0) < 0.025 { return "5:4" }
        if abs(ratio - 3.0 / 2.0) < 0.025 { return "3:2" }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = gcd(width, height)
        return "\(width / g):\(height / g)"
    }
}

public struct DisplayDeviceInfo: Identifiable {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltin: Bool
    public let isMain: Bool
    public let vendorID: UInt32
    public let productID: UInt32
    public let nativePixelWidth: Int
    public let nativePixelHeight: Int
    public let currentWidth: Int
    public let currentHeight: Int
    public let currentPixelWidth: Int
    public let currentPixelHeight: Int
    public let currentRefreshRate: Int
    public let currentIsHiDPI: Bool
    public let currentModeNumber: Int32?
    public let usesMonitorPanel: Bool
    /// System default mode reported by macOS (`isDefaultMode`), if present
    public let defaultNativeMode: DisplayModeOption?
    /// Native-aspect modes deduplicated by (width, height, isHiDPI), sorted descending with HiDPI paired above 1x
    public let nativeAspectModes: [DisplayModeOption]
    /// Non-native aspect ratio modes (4:3, 16:10 on 16:9 panel, etc.)
    public let otherAspectModes: [DisplayModeOption]
    /// Distinct available refresh rates for the currently active (width, height, isHiDPI)
    public let refreshRateModes: [DisplayModeOption]

    public var vendorHex: String { String(format: "%x", vendorID) }
    public var productHex: String { String(format: "%x", productID) }

    public var currentSummary: String {
        let tag = currentIsHiDPI ? "HiDPI" : "普通"
        if currentRefreshRate > 0 {
            return "\(currentWidth) × \(currentHeight) · \(tag) · \(currentRefreshRate)Hz"
        }
        return "\(currentWidth) × \(currentHeight) · \(tag)"
    }

    public var panelSubtitle: String {
        if currentIsHiDPI {
            return "面板原生 \(nativePixelWidth)×\(nativePixelHeight) · 渲染 \(currentPixelWidth)×\(currentPixelHeight)"
        }
        return "面板原生 \(nativePixelWidth)×\(nativePixelHeight)"
    }

    public func filteredModes(filter: DisplayModeFilter, includeOtherAspects: Bool) -> [DisplayModeOption] {
        var base = nativeAspectModes
        if includeOtherAspects {
            base += otherAspectModes
            base.sort { a, b in
                if a.width != b.width { return a.width > b.width }
                if a.height != b.height { return a.height > b.height }
                if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
                return a.refreshRate > b.refreshRate
            }
        }
        switch filter {
        case .hiDPIOnly:
            let hi = base.filter { $0.isHiDPI }
            return hi.isEmpty ? base : hi
        case .all:
            return base
        }
    }
}

/// Bridges macOS's MonitorPanel.framework (MPDisplayMgr / MPDisplay / MPDisplayMode),
/// the system display engine used by System Settings to expose macOS's full native
/// HiDPI + LoDPI mode table without virtual displays or legacy override plists.
private final class MonitorPanelBridge {
    static let shared = MonitorPanelBridge()
    private let isLoaded: Bool

    private init() {
        if let bundle = Bundle(path: "/System/Library/PrivateFrameworks/MonitorPanel.framework") {
            self.isLoaded = bundle.load()
        } else {
            self.isLoaded = false
        }
    }

    func fetchDisplaysByID() -> [CGDirectDisplayID: NSObject] {
        guard isLoaded,
              let mgrClass = NSClassFromString("MPDisplayMgr") as? NSObject.Type else {
            return [:]
        }
        let mgr = mgrClass.init()
        guard let list = mgr.value(forKey: "displays") as? [NSObject] else {
            return [:]
        }
        var map: [CGDirectDisplayID: NSObject] = [:]
        for disp in list {
            if let num = disp.value(forKey: "displayID") as? NSNumber {
                map[CGDirectDisplayID(num.uint32Value)] = disp
            }
        }
        return map
    }

    func setModeNumber(_ modeNumber: Int32, on mpDisplay: NSObject) -> Int32 {
        let sel = NSSelectorFromString("setModeNumber:")
        guard let cls: AnyClass = object_getClass(mpDisplay),
              let imp = class_getMethodImplementation(cls, sel) else {
            return -1
        }
        typealias SetModeNumFn = @convention(c) (AnyObject, Selector, Int32) -> Int32
        let fn = unsafeBitCast(imp, to: SetModeNumFn.self)
        return fn(mpDisplay, sel, modeNumber)
    }
}

@MainActor
public final class DisplayHiDPIStore: ObservableObject {
    @Published public var displays: [DisplayDeviceInfo] = []
    @Published public var selectedDisplayID: CGDirectDisplayID? = nil
    @Published public var modeFilter: DisplayModeFilter = .hiDPIOnly
    @Published public var showOtherAspects: Bool = false
    @Published public var canRevert: Bool = false
    @Published public var statusMessage: String? = nil

    /// Wraps a display mode switch so host floating panels can hide + flush to WindowServer
    /// BEFORE the synchronous mode switch executes, then reopen cleanly at the new menu bar anchor.
    public var onPerformDisplaySwitch: ((@escaping @MainActor () -> Void) -> Void)?

    private var mpDisplaysByID: [CGDirectDisplayID: NSObject] = [:]
    private var cgModesByDisplay: [CGDirectDisplayID: [CGDisplayMode]] = [:]
    private var lastAppliedRollback: RollbackTarget?
    private var screenObserver: NSObjectProtocol?
    private var screenChangeDebounceWorkItem: DispatchWorkItem?
    private var isUIActive: Bool = false
    private var needsRefreshOnOpen: Bool = false

    private enum RollbackTarget {
        case mpMode(displayID: CGDirectDisplayID, modeNumber: Int32)
        case cgMode(displayID: CGDirectDisplayID, mode: CGDisplayMode)
    }

    public init() {
        refreshDisplays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenParametersChanged()
            }
        }
    }

    deinit {
        screenChangeDebounceWorkItem?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    public func setUIActive(_ active: Bool) {
        isUIActive = active
        if active && needsRefreshOnOpen {
            refreshDisplays()
        }
    }

    private func handleScreenParametersChanged() {
        guard isUIActive else {
            needsRefreshOnOpen = true
            return
        }
        screenChangeDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshDisplays()
            }
        }
        screenChangeDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    public var selectedDisplay: DisplayDeviceInfo? {
        if let sel = selectedDisplayID, let match = displays.first(where: { $0.id == sel }) {
            return match
        }
        return displays.first
    }

    public var primarySummary: String {
        guard let main = displays.first(where: { $0.isMain }) ?? displays.first else {
            return "未检测到显示器"
        }
        return main.currentSummary
    }

    public func refreshDisplays() {
        needsRefreshOnOpen = false
        screenChangeDebounceWorkItem?.cancel()
        screenChangeDebounceWorkItem = nil

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displayIDs.count), &displayIDs, &count) == .success else {
            displays = []
            return
        }

        let mpMap = MonitorPanelBridge.shared.fetchDisplaysByID()
        let screens = NSScreen.screens
        var newDisplays: [DisplayDeviceInfo] = []
        var newCGModes: [CGDirectDisplayID: [CGDisplayMode]] = [:]

        for i in 0..<Int(count) {
            let did = displayIDs[i]
            let isBuiltin = CGDisplayIsBuiltin(did) != 0
            let isMain = CGDisplayIsMain(did) != 0
            let vendor = CGDisplayVendorNumber(did)
            let product = CGDisplayModelNumber(did)

            let screenName = screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == did
            }?.localizedName ?? (isBuiltin ? "内建显示器" : "外接显示器 #\(i + 1)")

            if let mpDisp = mpMap[did],
               let rawModes = mpDisp.value(forKey: "allModes") as? [NSObject],
               !rawModes.isEmpty {
                let info = buildDisplayInfoFromMonitorPanel(
                    did: did,
                    name: screenName,
                    isBuiltin: isBuiltin,
                    isMain: isMain,
                    vendor: vendor,
                    product: product,
                    mpDisplay: mpDisp,
                    rawModes: rawModes
                )
                newDisplays.append(info)
            } else {
                let (info, cgModes) = buildDisplayInfoFromCoreGraphics(
                    did: did,
                    name: screenName,
                    isBuiltin: isBuiltin,
                    isMain: isMain,
                    vendor: vendor,
                    product: product
                )
                newCGModes[did] = cgModes
                newDisplays.append(info)
            }
        }

        newDisplays.sort { a, b in
            if a.isMain != b.isMain { return a.isMain }
            return a.name < b.name
        }

        mpDisplaysByID = mpMap
        cgModesByDisplay = newCGModes
        displays = newDisplays
        if selectedDisplayID == nil || !newDisplays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = newDisplays.first?.id
        }
    }

    private func buildDisplayInfoFromMonitorPanel(
        did: CGDirectDisplayID,
        name: String,
        isBuiltin: Bool,
        isMain: Bool,
        vendor: UInt32,
        product: UInt32,
        mpDisplay: NSObject,
        rawModes: [NSObject]
    ) -> DisplayDeviceInfo {
        let curObj = mpDisplay.value(forKey: "currentMode") as? NSObject
        let natObj = mpDisplay.value(forKey: "nativeMode") as? NSObject

        let curW = (curObj?.value(forKey: "width") as? Int) ?? CGDisplayPixelsWide(did)
        let curH = (curObj?.value(forKey: "height") as? Int) ?? CGDisplayPixelsHigh(did)
        let curPW = (curObj?.value(forKey: "pixelsWide") as? Int) ?? curW
        let curPH = (curObj?.value(forKey: "pixelsHigh") as? Int) ?? curH
        let curHz = (curObj?.value(forKey: "refreshRate") as? Int) ?? 0
        let curHi = (curObj?.value(forKey: "isHiDPI") as? Bool) ?? (curPW > curW)
        let curNum = (curObj?.value(forKey: "modeNumber") as? NSNumber)?.int32Value

        let nativeW = (natObj?.value(forKey: "pixelsWide") as? Int) ?? curPW
        let nativeH = (natObj?.value(forKey: "pixelsHigh") as? Int) ?? curPH

        var allOptions: [DisplayModeOption] = []
        allOptions.reserveCapacity(rawModes.count)

        for m in rawModes {
            let w = (m.value(forKey: "width") as? Int) ?? 0
            let h = (m.value(forKey: "height") as? Int) ?? 0
            let pw = (m.value(forKey: "pixelsWide") as? Int) ?? w
            let ph = (m.value(forKey: "pixelsHigh") as? Int) ?? h
            let hz = (m.value(forKey: "refreshRate") as? Int) ?? 0
            let hi = (m.value(forKey: "isHiDPI") as? Bool) ?? (pw > w)
            let isDef = (m.value(forKey: "isDefaultMode") as? Bool) ?? false
            let isNat = (m.value(forKey: "isNativeMode") as? Bool) ?? false
            let isTV = (m.value(forKey: "isTVMode") as? Bool) ?? false
            let modeNum = (m.value(forKey: "modeNumber") as? NSNumber)?.int32Value ?? -1

            guard w >= 640, h >= 480, modeNum >= 0 else { continue }
            let isCur: Bool
            if let curNum {
                isCur = (modeNum == curNum)
            } else {
                isCur = (w == curW && h == curH && hi == curHi && hz == curHz)
            }
            if isTV && !isCur { continue }

            let opt = DisplayModeOption(
                id: "mp-\(modeNum)-\(w)x\(h)-\(hi ? "hi" : "lo")-\(hz)",
                modeNumber: modeNum,
                width: w,
                height: h,
                pixelWidth: pw,
                pixelHeight: ph,
                refreshRate: hz,
                isHiDPI: hi,
                isDefault: isDef,
                isNative: isNat,
                isCurrent: isCur,
                cgModeIndex: nil
            )
            allOptions.append(opt)
        }

        return finalizeDisplayInfo(
            did: did,
            name: name,
            isBuiltin: isBuiltin,
            isMain: isMain,
            vendor: vendor,
            product: product,
            nativeW: nativeW,
            nativeH: nativeH,
            curW: curW,
            curH: curH,
            curPW: curPW,
            curPH: curPH,
            curHz: curHz,
            curHi: curHi,
            curNum: curNum,
            usesMonitorPanel: true,
            allOptions: allOptions
        )
    }

    private func buildDisplayInfoFromCoreGraphics(
        did: CGDirectDisplayID,
        name: String,
        isBuiltin: Bool,
        isMain: Bool,
        vendor: UInt32,
        product: UInt32
    ) -> (DisplayDeviceInfo, [CGDisplayMode]) {
        let kNativeFlag: UInt32 = 0x0200_0000
        let kDefaultFlag: UInt32 = 0x0000_0004

        let currentMode = CGDisplayCopyDisplayMode(did)
        let curIOID = currentMode?.ioDisplayModeID
        let curW = currentMode?.width ?? CGDisplayPixelsWide(did)
        let curH = currentMode?.height ?? CGDisplayPixelsHigh(did)
        let curPW = currentMode?.pixelWidth ?? curW
        let curPH = currentMode?.pixelHeight ?? curH
        let curHz = Int(round(currentMode?.refreshRate ?? 0))
        let curHi = curPW > curW

        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let cgModes = (CGDisplayCopyAllDisplayModes(did, options) as? [CGDisplayMode]) ?? []

        var nativeW = curPW
        var nativeH = curPH
        var bestArea = 0
        for m in cgModes where m.isUsableForDesktopGUI() {
            if (m.ioFlags & kNativeFlag) != 0 {
                let area = m.pixelWidth * m.pixelHeight
                if area > bestArea {
                    bestArea = area
                    nativeW = m.pixelWidth
                    nativeH = m.pixelHeight
                }
            }
        }

        var allOptions: [DisplayModeOption] = []
        for (idx, m) in cgModes.enumerated() where m.isUsableForDesktopGUI() {
            let w = m.width
            let h = m.height
            let pw = m.pixelWidth
            let ph = m.pixelHeight
            let hz = Int(round(m.refreshRate))
            let hi = pw > w
            let isDef = (m.ioFlags & kDefaultFlag) != 0
            let isNat = (m.ioFlags & kNativeFlag) != 0
            let isCur: Bool
            if let curIOID {
                isCur = (m.ioDisplayModeID == curIOID)
            } else {
                isCur = (w == curW && h == curH && hi == curHi && hz == curHz)
            }

            allOptions.append(DisplayModeOption(
                id: "cg-\(idx)-\(w)x\(h)-\(hi ? "hi" : "lo")-\(hz)",
                modeNumber: Int32(idx),
                width: w,
                height: h,
                pixelWidth: pw,
                pixelHeight: ph,
                refreshRate: hz,
                isHiDPI: hi,
                isDefault: isDef,
                isNative: isNat,
                isCurrent: isCur,
                cgModeIndex: idx
            ))
        }

        let info = finalizeDisplayInfo(
            did: did,
            name: name,
            isBuiltin: isBuiltin,
            isMain: isMain,
            vendor: vendor,
            product: product,
            nativeW: nativeW,
            nativeH: nativeH,
            curW: curW,
            curH: curH,
            curPW: curPW,
            curPH: curPH,
            curHz: curHz,
            curHi: curHi,
            curNum: nil,
            usesMonitorPanel: false,
            allOptions: allOptions
        )
        return (info, cgModes)
    }

    private func finalizeDisplayInfo(
        did: CGDirectDisplayID,
        name: String,
        isBuiltin: Bool,
        isMain: Bool,
        vendor: UInt32,
        product: UInt32,
        nativeW: Int,
        nativeH: Int,
        curW: Int,
        curH: Int,
        curPW: Int,
        curPH: Int,
        curHz: Int,
        curHi: Bool,
        curNum: Int32?,
        usesMonitorPanel: Bool,
        allOptions: [DisplayModeOption]
    ) -> DisplayDeviceInfo {
        let nativeAspect = Double(max(1, nativeW)) / Double(max(1, nativeH))

        // 1. Collect distinct refresh rates for the currently active (width, height, isHiDPI)
        var hzMap: [Int: DisplayModeOption] = [:]
        for opt in allOptions where opt.width == curW && opt.height == curH && opt.isHiDPI == curHi && opt.refreshRate > 0 {
            if opt.refreshRate >= 50 || opt.isCurrent {
                if hzMap[opt.refreshRate] == nil || opt.isCurrent {
                    hzMap[opt.refreshRate] = opt
                }
            }
        }
        let sortedRefreshRates = hzMap.values.sorted { $0.refreshRate > $1.refreshRate }

        // 2. Deduplicate by (width, height, isHiDPI) picking best Hz (prefer current Hz, else highest Hz)
        struct ResScaleKey: Hashable {
            let width: Int
            let height: Int
            let isHiDPI: Bool
        }
        var bestByResScale: [ResScaleKey: DisplayModeOption] = [:]
        for opt in allOptions {
            let key = ResScaleKey(width: opt.width, height: opt.height, isHiDPI: opt.isHiDPI)
            if let existing = bestByResScale[key] {
                let optBetter: Bool
                if opt.isCurrent != existing.isCurrent {
                    optBetter = opt.isCurrent
                } else if (opt.refreshRate == curHz) != (existing.refreshRate == curHz) {
                    optBetter = (opt.refreshRate == curHz)
                } else if opt.refreshRate != existing.refreshRate {
                    optBetter = opt.refreshRate > existing.refreshRate
                } else {
                    optBetter = opt.isDefault && !existing.isDefault
                }
                if optBetter {
                    bestByResScale[key] = opt
                }
            } else {
                bestByResScale[key] = opt
            }
        }

        // 3. Split into native-aspect vs other-aspect modes
        var nativeAspectList: [DisplayModeOption] = []
        var otherAspectList: [DisplayModeOption] = []

        for opt in bestByResScale.values {
            let aspect = Double(max(1, opt.width)) / Double(max(1, opt.height))
            let aspectDelta = abs(aspect - nativeAspect) / nativeAspect
            let isNativeAspect = aspectDelta < 0.025
            let isPracticalSize = opt.width >= 960 || opt.isCurrent

            if isNativeAspect && isPracticalSize {
                nativeAspectList.append(opt)
            } else if opt.width >= 800 || opt.isCurrent {
                otherAspectList.append(opt)
            }
        }

        let sortModes: (DisplayModeOption, DisplayModeOption) -> Bool = { a, b in
            if a.width != b.width { return a.width > b.width }
            if a.height != b.height { return a.height > b.height }
            if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
            return a.refreshRate > b.refreshRate
        }
        nativeAspectList.sort(by: sortModes)
        otherAspectList.sort(by: sortModes)

        let defaultMode = nativeAspectList.first(where: { $0.isDefault })

        return DisplayDeviceInfo(
            id: did,
            name: name,
            isBuiltin: isBuiltin,
            isMain: isMain,
            vendorID: vendor,
            productID: product,
            nativePixelWidth: nativeW,
            nativePixelHeight: nativeH,
            currentWidth: curW,
            currentHeight: curH,
            currentPixelWidth: curPW,
            currentPixelHeight: curPH,
            currentRefreshRate: curHz,
            currentIsHiDPI: curHi,
            currentModeNumber: curNum,
            usesMonitorPanel: usesMonitorPanel,
            defaultNativeMode: defaultMode,
            nativeAspectModes: nativeAspectList,
            otherAspectModes: otherAspectList,
            refreshRateModes: sortedRefreshRates
        )
    }

    public func applyMode(_ option: DisplayModeOption, for displayID: CGDirectDisplayID) {
        guard !option.isCurrent else { return }

        // Capture rollback target before switching, but commit it only after switch succeeds
        let pendingRollback: RollbackTarget?
        if let disp = displays.first(where: { $0.id == displayID }),
           disp.usesMonitorPanel,
           let curNum = disp.currentModeNumber {
            pendingRollback = .mpMode(displayID: displayID, modeNumber: curNum)
        } else if let prevCG = CGDisplayCopyDisplayMode(displayID) {
            pendingRollback = .cgMode(displayID: displayID, mode: prevCG)
        } else {
            pendingRollback = nil
        }

        let hzStr = option.refreshRate > 0 ? " @ \(option.refreshRate)Hz" : ""
        let successMessage = "已切换至 \(option.resolutionText) \(option.isHiDPI ? "HiDPI" : "普通模式")\(hzStr)"

        let executeSwitch: @MainActor () -> Void = { [weak self] in
            guard let self else { return }

            // Preferred path: MonitorPanel.framework setModeNumber:
            if let mpDisp = self.mpDisplaysByID[displayID], option.cgModeIndex == nil {
                let rc = MonitorPanelBridge.shared.setModeNumber(option.modeNumber, on: mpDisp)
                if rc == 0 {
                    if let pendingRollback {
                        self.lastAppliedRollback = pendingRollback
                        self.canRevert = true
                    }
                    self.statusMessage = successMessage
                    self.refreshDisplays()
                } else {
                    self.statusMessage = "切换失败 (错误码 \(rc))"
                }
                return
            }

            // Fallback path: CoreGraphics public API
            guard let cgIndex = option.cgModeIndex,
                  let modes = self.cgModesByDisplay[displayID],
                  cgIndex >= 0 && cgIndex < modes.count else {
                return
            }
            if self.applyCoreGraphicsMode(modes[cgIndex], displayID: displayID) {
                if let pendingRollback {
                    self.lastAppliedRollback = pendingRollback
                    self.canRevert = true
                }
                self.statusMessage = successMessage
                self.refreshDisplays()
            }
        }

        if let wrapper = onPerformDisplaySwitch {
            wrapper(executeSwitch)
        } else {
            executeSwitch()
        }
    }

    public func revertLastMode() {
        guard let rollback = lastAppliedRollback else { return }
        let executeRevert: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            switch rollback {
            case .mpMode(let did, let modeNum):
                guard let mpDisp = self.mpDisplaysByID[did] else {
                    self.statusMessage = "未找到目标显示器，无法恢复"
                    return
                }
                let rc = MonitorPanelBridge.shared.setModeNumber(modeNum, on: mpDisp)
                if rc == 0 {
                    self.lastAppliedRollback = nil
                    self.canRevert = false
                    self.statusMessage = "已恢复上一个分辨率"
                    self.refreshDisplays()
                } else {
                    self.statusMessage = "恢复失败 (错误码 \(rc))"
                }
            case .cgMode(let did, let cgMode):
                if self.applyCoreGraphicsMode(cgMode, displayID: did) {
                    self.lastAppliedRollback = nil
                    self.canRevert = false
                    self.statusMessage = "已恢复上一个分辨率"
                    self.refreshDisplays()
                }
            }
        }

        if let wrapper = onPerformDisplaySwitch {
            wrapper(executeRevert)
        } else {
            executeRevert()
        }
    }

    private func applyCoreGraphicsMode(_ targetMode: CGDisplayMode, displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else {
            statusMessage = "无法初始化显示器配置"
            return false
        }
        let configErr = CGConfigureDisplayWithDisplayMode(cfg, displayID, targetMode, nil)
        guard configErr == .success else {
            CGCancelDisplayConfiguration(cfg)
            statusMessage = "配置显示模式失败 (错误码 \(configErr.rawValue))"
            return false
        }
        let completeErr = CGCompleteDisplayConfiguration(cfg, .permanently)
        guard completeErr == .success else {
            statusMessage = "切换失败 (错误码 \(completeErr.rawValue))"
            return false
        }
        return true
    }

    public func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

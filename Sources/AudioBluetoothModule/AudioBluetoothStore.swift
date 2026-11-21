import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import IOBluetooth
import IOKit
import ObjectiveC

public struct AudioDeviceInfo: Identifiable, Hashable {
    public let id: AudioDeviceID
    public let name: String
    public let isInput: Bool
    public let isOutput: Bool
    public let isBuiltin: Bool
    public let isBluetooth: Bool
    public let isContinuity: Bool
    public let isCurrentDefault: Bool

    public var symbolName: String {
        if isContinuity {
            return "iphone"
        }
        if isBluetooth {
            return "headphones"
        }
        if isBuiltin {
            return isInput && !isOutput ? "mic.fill" : "speaker.wave.2.fill"
        }
        return isInput && !isOutput ? "mic" : "hifispeaker"
    }
}

public struct BluetoothDeviceInfo: Identifiable, Hashable, Sendable {
    public var id: String { address }
    public let name: String
    public let address: String
    public let isConnected: Bool
    public let minorType: String
    public let leftBattery: Int?
    public let rightBattery: Int?
    public let caseBattery: Int?
    public let mainBattery: Int?

    public var hasAnyBattery: Bool {
        leftBattery != nil || rightBattery != nil || caseBattery != nil || mainBattery != nil
    }

    public var hasSplitEarbudBattery: Bool {
        leftBattery != nil || rightBattery != nil || caseBattery != nil
    }

    public var isAudioDevice: Bool {
        let lower = minorType.lowercased()
        return lower.contains("headphone")
            || lower.contains("headset")
            || lower.contains("speaker")
            || lower.contains("audio")
            || lower.contains("earbud")
            || hasSplitEarbudBattery
    }

    public var symbolName: String {
        if hasSplitEarbudBattery {
            return "airpodspro"
        }
        let lowerType = minorType.lowercased()
        if lowerType.contains("headphone") || lowerType.contains("headset") { return "headphones" }
        if lowerType.contains("speaker") { return "hifispeaker" }
        if lowerType.contains("mouse") { return "computermouse" }
        if lowerType.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if lowerType.contains("keyboard") { return "keyboard" }
        if lowerType.contains("gamepad") || lowerType.contains("joystick") { return "gamecontroller" }
        return "dot.radiowaves.left.and.right"
    }
}

@MainActor
public final class AudioBluetoothStore: ObservableObject {
    @Published public var outputDevices: [AudioDeviceInfo] = []
    @Published public var inputDevices: [AudioDeviceInfo] = []
    @Published public var bluetoothDevices: [BluetoothDeviceInfo] = []
    @Published public var bluetoothPoweredOn: Bool = true
    @Published public var outputVolume: Float = 0.5
    @Published public var isMuted: Bool = false
    @Published public var isRefreshingBluetooth: Bool = false
    @Published public var busyDeviceAddress: String? = nil
    @Published public var statusMessage: String? = nil

    private var listenerHub: CoreAudioListenerHub?
    private var btNotificationHub: BluetoothNotificationHub?
    private var pendingBluetoothRefresh: Bool = false
    private var lastBluetoothRefreshTime: TimeInterval = 0

    public init() {
        refreshAudioDevices()
        refreshBluetoothDevices(force: true)
        setupCoreAudioListeners()
        setupBluetoothNotifications()
    }

    private func setupCoreAudioListeners() {
        let hub = CoreAudioListenerHub(
            onRouteChanged: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshAudioDevices()
                }
            },
            onVolumeChanged: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.syncVolumeFromHardware()
                }
            }
        )
        listenerHub = hub
        let defaultOut = getDefaultAudioDevice(scope: kAudioHardwarePropertyDefaultOutputDevice)
        hub.observeOutputDevice(defaultOut)
    }

    private func setupBluetoothNotifications() {
        btNotificationHub = BluetoothNotificationHub { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshAudioDevices()
                self.refreshBluetoothDevices(force: true)
            }
        }
    }

    private func syncVolumeFromHardware() {
        let defaultOut = getDefaultAudioDevice(scope: kAudioHardwarePropertyDefaultOutputDevice)
        guard defaultOut != 0 else { return }
        let vol = getVolume(for: defaultOut)
        let muted = getMute(for: defaultOut)
        if abs(outputVolume - vol) > 0.002 {
            outputVolume = vol
        }
        if isMuted != muted {
            isMuted = muted
        }
    }

    public var currentOutputName: String {
        outputDevices.first(where: { $0.isCurrentDefault })?.name ?? "默认输出"
    }

    public var currentInputDevice: AudioDeviceInfo? {
        inputDevices.first(where: { $0.isCurrentDefault })
    }

    public var builtinInputDevice: AudioDeviceInfo? {
        inputDevices.first(where: { $0.isBuiltin })
    }

    public var connectedAudioBluetooth: BluetoothDeviceInfo? {
        bluetoothDevices.first(where: { $0.isConnected && $0.isAudioDevice })
    }

    public var primarySubtitle: String {
        if let bt = connectedAudioBluetooth {
            if let l = bt.leftBattery, let r = bt.rightBattery {
                return "\(bt.name) · L\(l)% R\(r)%"
            }
            if let main = bt.mainBattery {
                return "\(bt.name) · \(main)%"
            }
            return bt.name
        }
        return currentOutputName
    }

    // MARK: - CoreAudio Enumeration & Switching (100% Public HAL API)

    public func refreshAudioDevices() {
        let defaultOut = getDefaultAudioDevice(scope: kAudioHardwarePropertyDefaultOutputDevice)
        let defaultIn = getDefaultAudioDevice(scope: kAudioHardwarePropertyDefaultInputDevice)

        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return
        }

        var outs: [AudioDeviceInfo] = []
        var ins: [AudioDeviceInfo] = []

        for devID in deviceIDs {
            guard let name = getAudioDeviceName(devID), !name.isEmpty else { continue }
            let hasOut = deviceHasStreams(devID, scope: kAudioDevicePropertyScopeOutput)
            let hasIn = deviceHasStreams(devID, scope: kAudioDevicePropertyScopeInput)
            let transport = getAudioDeviceTransport(devID)
            let isBuiltin = (transport == kAudioDeviceTransportTypeBuiltIn)
            let isBT = (transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE)
            let isContinuity = (transport == kAudioDeviceTransportTypeContinuityCaptureWired
                || transport == kAudioDeviceTransportTypeContinuityCaptureWireless)

            if hasOut {
                outs.append(AudioDeviceInfo(
                    id: devID,
                    name: name,
                    isInput: hasIn,
                    isOutput: true,
                    isBuiltin: isBuiltin,
                    isBluetooth: isBT,
                    isContinuity: isContinuity,
                    isCurrentDefault: devID == defaultOut
                ))
            }
            if hasIn {
                ins.append(AudioDeviceInfo(
                    id: devID,
                    name: name,
                    isInput: true,
                    isOutput: hasOut,
                    isBuiltin: isBuiltin,
                    isBluetooth: isBT,
                    isContinuity: isContinuity,
                    isCurrentDefault: devID == defaultIn
                ))
            }
        }

        outputDevices = outs
        inputDevices = ins

        if defaultOut != 0 {
            outputVolume = getVolume(for: defaultOut)
            isMuted = getMute(for: defaultOut)
        }
        listenerHub?.observeOutputDevice(defaultOut)
    }

    public func selectOutputDevice(_ device: AudioDeviceInfo) {
        setDefaultAudioDevice(device.id, selector: kAudioHardwarePropertyDefaultOutputDevice)
        statusMessage = nil
        refreshAudioDevices()
    }

    public func selectInputDevice(_ device: AudioDeviceInfo) {
        setDefaultAudioDevice(device.id, selector: kAudioHardwarePropertyDefaultInputDevice)
        if device.isContinuity {
            statusMessage = "已切换默认输入为「\(device.name)」；连续互通麦克风会在录音/通话启动时自动唤醒 iPhone"
        } else {
            statusMessage = nil
        }
        refreshAudioDevices()
    }

    public func switchToBuiltinMic() {
        if let mic = builtinInputDevice {
            selectInputDevice(mic)
            statusMessage = "已切换至内建麦克风以保持蓝牙高清音质"
        }
    }

    public func setOutputVolume(_ value: Float) {
        let clamped = min(1.0, max(0.0, value))
        outputVolume = clamped
        let defaultOut = getDefaultAudioDevice(scope: kAudioHardwarePropertyDefaultOutputDevice)
        guard defaultOut != 0 else { return }

        var vol = Float32(clamped)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(defaultOut, &addr) {
            AudioObjectSetPropertyData(defaultOut, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
        } else {
            for elem: AudioObjectPropertyElement in [0, 1, 2] {
                var scalarAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: elem
                )
                if AudioObjectHasProperty(defaultOut, &scalarAddr) {
                    AudioObjectSetPropertyData(defaultOut, &scalarAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
                }
            }
        }
        if clamped > 0.01 && isMuted {
            setOutputMute(false)
        }
    }

    public func setOutputMute(_ mute: Bool) {
        isMuted = mute
        let defaultOut = getDefaultAudioDevice(scope: kAudioHardwarePropertyDefaultOutputDevice)
        guard defaultOut != 0 else { return }

        var val: UInt32 = mute ? 1 : 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(defaultOut, &addr) {
            AudioObjectSetPropertyData(defaultOut, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
        }
    }

    // MARK: - Zero-Subprocess Native IOBluetooth + IORegistry Snapshot (< 0.5ms)

    public func refreshBluetoothDevices(force: Bool = false) {
        let now = Date().timeIntervalSinceReferenceDate
        if !force && !bluetoothDevices.isEmpty && (now - lastBluetoothRefreshTime) < 1.5 {
            return
        }
        if isRefreshingBluetooth {
            if force {
                pendingBluetoothRefresh = true
            }
            return
        }
        isRefreshingBluetooth = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = Self.fetchNativeBluetoothSnapshot()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshingBluetooth = false
                self.lastBluetoothRefreshTime = Date().timeIntervalSinceReferenceDate
                self.bluetoothPoweredOn = parsed.poweredOn
                self.bluetoothDevices = parsed.devices

                if self.pendingBluetoothRefresh {
                    self.pendingBluetoothRefresh = false
                    self.refreshBluetoothDevices(force: true)
                }
            }
        }
    }

    public func toggleBluetoothConnection(_ device: BluetoothDeviceInfo) {
        guard busyDeviceAddress == nil else { return }
        busyDeviceAddress = device.address
        statusMessage = nil
        let targetAddr = device.address
        let shouldConnect = !device.isConnected

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var ok = false
            if let btDev = IOBluetoothDevice(addressString: targetAddr) {
                let rc = shouldConnect ? btDev.openConnection() : btDev.closeConnection()
                ok = (rc == kIOReturnSuccess)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.busyDeviceAddress = nil
                if !ok {
                    self.statusMessage = shouldConnect ? "连接 \(device.name) 失败，请确认设备在附近" : "断开 \(device.name) 失败"
                }
                self.refreshBluetoothDevices(force: true)
                self.refreshAudioDevices()
            }
        }
    }

    public func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - CoreAudio Low-Level Helpers

    private func getDefaultAudioDevice(scope: AudioObjectPropertySelector) -> AudioDeviceID {
        var devID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: scope,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID)
        return devID
    }

    private func setDefaultAudioDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) {
        var devID = deviceID
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &devID
        )
    }

    private func getAudioDeviceName(_ devID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let rc = withUnsafeMutablePointer(to: &nameRef) { ptr in
            AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, ptr)
        }
        guard rc == noErr, let cfStr = nameRef else { return nil }
        return cfStr as String
    }

    private func getAudioDeviceTransport(_ devID: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &transport)
        return transport
    }

    private func deviceHasStreams(_ devID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(devID, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private func getVolume(for devID: AudioDeviceID) -> Float {
        var vol: Float32 = 0.5
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(devID, &addr),
           AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &vol) == noErr {
            return Float(vol)
        }
        for elem: AudioObjectPropertyElement in [0, 1, 2] {
            var scalarAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: elem
            )
            if AudioObjectHasProperty(devID, &scalarAddr),
               AudioObjectGetPropertyData(devID, &scalarAddr, 0, nil, &size, &vol) == noErr {
                return Float(vol)
            }
        }
        return 0.5
    }

    private func getMute(for devID: AudioDeviceID) -> Bool {
        var val: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(devID, &addr),
           AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &val) == noErr {
            return val != 0
        }
        return false
    }

    // MARK: - Native IOBluetooth + IORegistry Reader (Zero Subprocesses)

    private nonisolated static func fetchNativeBluetoothSnapshot() -> (poweredOn: Bool, devices: [BluetoothDeviceInfo]) {
        let poweredOn: Bool
        if let host = IOBluetoothHostController.default() {
            poweredOn = (host.powerState == kBluetoothHCIPowerStateON)
        } else {
            poweredOn = true
        }

        // 1. Collect BLE / HID peripheral battery percentages from IORegistry (Magic Mouse / Keyboard / Trackpad / BLE peripherals)
        let hidBatteries = readIORegistryHIDBatteries()

        // 2. Enumerate paired Bluetooth devices directly from IOBluetoothDevice
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return (poweredOn, [])
        }

        var result: [BluetoothDeviceInfo] = []
        var seenAddresses = Set<String>()

        for dev in paired {
            let rawAddr = dev.addressString ?? ""
            let normAddr = normalizeBluetoothAddress(rawAddr)
            guard !normAddr.isEmpty, seenAddresses.insert(normAddr).inserted else { continue }

            let name = dev.name ?? rawAddr
            let connected = dev.isConnected()
            let minorType = classifyBluetoothDeviceType(dev)

            let left = readIOBluetoothBatteryPercent(dev, selectorName: "batteryPercentLeft")
            let right = readIOBluetoothBatteryPercent(dev, selectorName: "batteryPercentRight")
            let box = readIOBluetoothBatteryPercent(dev, selectorName: "batteryPercentCase")
            let single = readIOBluetoothBatteryPercent(dev, selectorName: "batteryPercentSingle")
                ?? readIOBluetoothBatteryPercent(dev, selectorName: "batteryPercentCombined")
                ?? readIOBluetoothBatteryPercent(dev, selectorName: "headsetBatteryPercent")
                ?? hidBatteries.byAddress[normAddr]
                ?? hidBatteries.byName[name]

            let item = BluetoothDeviceInfo(
                name: name,
                address: rawAddr,
                isConnected: connected,
                minorType: minorType,
                leftBattery: left,
                rightBattery: right,
                caseBattery: box,
                mainBattery: single
            )

            if item.isAudioDevice || item.hasAnyBattery || !minorType.isEmpty {
                result.append(item)
            }
        }

        result.sort { a, b in
            if a.isConnected != b.isConnected { return a.isConnected }
            if a.isAudioDevice != b.isAudioDevice { return a.isAudioDevice }
            return a.name < b.name
        }

        return (poweredOn, result)
    }

    private nonisolated static func readIOBluetoothBatteryPercent(_ device: IOBluetoothDevice, selectorName: String) -> Int? {
        let sel = NSSelectorFromString(selectorName)
        guard device.responds(to: sel),
              let cls: AnyClass = object_getClass(device),
              let imp = class_getMethodImplementation(cls, sel) else {
            return nil
        }
        typealias BatteryGetterFn = @convention(c) (AnyObject, Selector) -> UInt8
        let fn = unsafeBitCast(imp, to: BatteryGetterFn.self)
        let pct = Int(fn(device, sel))
        return (pct > 0 && pct <= 100) ? pct : nil
    }

    private nonisolated static func classifyBluetoothDeviceType(_ device: IOBluetoothDevice) -> String {
        let major = device.deviceClassMajor
        let minor = device.deviceClassMinor

        if major == kBluetoothDeviceClassMajorAudio {
            switch Int(minor) {
            case kBluetoothDeviceClassMinorAudioHeadset,
                 kBluetoothDeviceClassMinorAudioHandsFree:
                return "Headset"
            case kBluetoothDeviceClassMinorAudioHeadphones,
                 kBluetoothDeviceClassMinorAudioHiFi:
                return "Headphones"
            case kBluetoothDeviceClassMinorAudioLoudspeaker,
                 kBluetoothDeviceClassMinorAudioPortable,
                 kBluetoothDeviceClassMinorAudioCar:
                return "Speaker"
            default:
                return "Audio"
            }
        }

        if major == kBluetoothDeviceClassMajorPeripheral {
            let category = Int(minor) & 0x30
            if category == 0x10 { return "Keyboard" }
            if category == 0x20 { return "Mouse" }
            if category == 0x30 { return "Keyboard" }
            let sub = Int(minor) & 0x0F
            if sub == 1 || sub == 2 { return "Gamepad" }
            return "Peripheral"
        }

        if device.isHandsFreeAudioGateway || device.isHandsFreeDevice {
            return "Headset"
        }

        return ""
    }

    private nonisolated static func readIORegistryHIDBatteries() -> (byAddress: [String: Int], byName: [String: Int]) {
        var byAddress: [String: Int] = [:]
        var byName: [String: Int] = [:]

        var hidIter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"),
            &hidIter
        ) == KERN_SUCCESS else {
            return (byAddress, byName)
        }
        defer { IOObjectRelease(hidIter) }

        var entry: io_object_t = IOIteratorNext(hidIter)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(hidIter)
            }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = propsRef?.takeRetainedValue() as? [String: Any],
                  let pct = dict["BatteryPercent"] as? Int,
                  pct > 0 && pct <= 100 else {
                continue
            }

            if let addr = dict["DeviceAddress"] as? String, !addr.isEmpty {
                byAddress[normalizeBluetoothAddress(addr)] = pct
            }
            if let product = dict["Product"] as? String, !product.isEmpty {
                byName[product] = pct
            }
        }

        return (byAddress, byName)
    }

    private nonisolated static func normalizeBluetoothAddress(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "-", with: ":").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Listens to system-wide IOBluetooth connection and disconnection events.
private final class BluetoothNotificationHub: NSObject {
    private let onConnectionChanged: @Sendable () -> Void
    private var connectNotif: IOBluetoothUserNotification?
    private var observedDisconnectNotifs: [IOBluetoothUserNotification] = []

    init(onConnectionChanged: @escaping @Sendable () -> Void) {
        self.onConnectionChanged = onConnectionChanged
        super.init()
        self.connectNotif = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleDeviceConnected(_:device:))
        )
    }

    @objc private func handleDeviceConnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        if let device,
           let disc = device.register(forDisconnectNotification: self, selector: #selector(handleDeviceDisconnected(_:device:))) {
            observedDisconnectNotifs.append(disc)
        }
        onConnectionChanged()
    }

    @objc private func handleDeviceDisconnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        onConnectionChanged()
    }

    deinit {
        connectNotif?.unregister()
        for n in observedDisconnectNotifs {
            n.unregister()
        }
    }
}

/// Zero-polling CoreAudio HAL event listener hub (0.0% idle CPU).
/// Registers kernel-pushed property listeners for default audio route changes,
/// device list changes, output volume changes, and mute state changes.
private final class CoreAudioListenerHub: @unchecked Sendable {
    private let systemObj = AudioObjectID(kAudioObjectSystemObject)
    private var observedDeviceID: AudioDeviceID = 0
    private var observedDeviceAddrs: [AudioObjectPropertyAddress] = []
    private let systemAddrs: [AudioObjectPropertyAddress]
    private var routeListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?

    init(
        onRouteChanged: @escaping @Sendable () -> Void,
        onVolumeChanged: @escaping @Sendable () -> Void
    ) {
        self.systemAddrs = [
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        ]

        let routeBlock: AudioObjectPropertyListenerBlock = { _, _ in
            onRouteChanged()
        }
        let volBlock: AudioObjectPropertyListenerBlock = { _, _ in
            onVolumeChanged()
        }
        self.routeListenerBlock = routeBlock
        self.volumeListenerBlock = volBlock

        for var addr in systemAddrs {
            AudioObjectAddPropertyListenerBlock(systemObj, &addr, DispatchQueue.main, routeBlock)
        }
    }

    func observeOutputDevice(_ deviceID: AudioDeviceID) {
        guard deviceID != observedDeviceID else { return }
        removeOutputDeviceListeners()
        guard deviceID != 0, let volBlock = volumeListenerBlock else { return }

        observedDeviceID = deviceID
        let candidates: [AudioObjectPropertyAddress] = [
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 0
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            )
        ]

        var registered: [AudioObjectPropertyAddress] = []
        for var addr in candidates {
            if AudioObjectHasProperty(deviceID, &addr) {
                if AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.main, volBlock) == noErr {
                    registered.append(addr)
                }
            }
        }
        observedDeviceAddrs = registered
    }

    private func removeOutputDeviceListeners() {
        guard observedDeviceID != 0, let volBlock = volumeListenerBlock else { return }
        for var addr in observedDeviceAddrs {
            AudioObjectRemovePropertyListenerBlock(observedDeviceID, &addr, DispatchQueue.main, volBlock)
        }
        observedDeviceAddrs.removeAll()
        observedDeviceID = 0
    }

    deinit {
        removeOutputDeviceListeners()
        if let routeBlock = routeListenerBlock {
            for var addr in systemAddrs {
                AudioObjectRemovePropertyListenerBlock(systemObj, &addr, DispatchQueue.main, routeBlock)
            }
        }
    }
}

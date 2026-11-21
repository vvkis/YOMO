import Foundation
import IOKit.pwr_mgt

public enum KeepAwakeDuration: Int, CaseIterable, Identifiable {
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case hours2 = 120
    case indefinite = 0

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .minutes15: return "15 分钟"
        case .minutes30: return "30 分钟"
        case .hour1: return "1 小时"
        case .hours2: return "2 小时"
        case .indefinite: return "持续常亮"
        }
    }
}

@MainActor
public final class KeepAwakeStore: ObservableObject {
    @Published public var isActive: Bool = false
    @Published public var selectedDuration: KeepAwakeDuration = .indefinite
    @Published public var remainingSeconds: Int? = nil

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var expirationDate: Date?
    private var countdownTimer: Timer?

    public init() {}

    deinit {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
        }
    }

    public func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(duration: selectedDuration)
        }
    }

    public func activate(duration: KeepAwakeDuration) {
        selectedDuration = duration
        countdownTimer?.invalidate()
        countdownTimer = nil

        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            hasAssertion = false
        }

        let timeoutSeconds = duration.rawValue * 60
        var props: [String: Any] = [
            kIOPMAssertionTypeKey: kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionNameKey: "YOMO KeepAwake",
            kIOPMAssertionLevelKey: NSNumber(value: kIOPMAssertionLevelOn)
        ]
        if timeoutSeconds > 0 {
            props[kIOPMAssertionTimeoutKey] = NSNumber(value: timeoutSeconds)
            props[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionTurnOff
        }

        var newID: IOPMAssertionID = 0
        let rc = IOPMAssertionCreateWithProperties(props as CFDictionary, &newID)
        if rc == kIOReturnSuccess {
            assertionID = newID
            hasAssertion = true
        }

        isActive = hasAssertion
        guard hasAssertion else {
            expirationDate = nil
            remainingSeconds = nil
            return
        }

        if duration == .indefinite {
            expirationDate = nil
            remainingSeconds = nil
        } else {
            let end = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
            expirationDate = end
            remainingSeconds = timeoutSeconds
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateRemainingTime()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            countdownTimer = timer
        }
    }

    private func updateRemainingTime() {
        guard let end = expirationDate else { return }
        let rem = Int(ceil(end.timeIntervalSinceNow))
        if rem <= 0 {
            deactivate()
        } else if remainingSeconds != rem {
            remainingSeconds = rem
        }
    }

    public func deactivate() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        expirationDate = nil
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            hasAssertion = false
        }
        isActive = false
        remainingSeconds = nil
    }

    public var statusSubtitle: String {
        guard isActive else { return "已关闭" }
        if let rem = remainingSeconds {
            let h = rem / 3600
            let m = (rem % 3600) / 60
            let s = rem % 60
            if h > 0 {
                return String(format: "剩余 %d:%02d:%02d", h, m, s)
            }
            return String(format: "剩余 %02d:%02d", m, s)
        }
        return "持续防息屏"
    }
}

import Foundation
import IOKit.pwr_mgt

/// Holds an IOPM assertion so USB disks and the system don't idle-sleep mid-transfer.
@MainActor
public final class TransferPowerAssertion {
    public static let shared = TransferPowerAssertion()

    private var assertionID: IOPMAssertionID = 0
    private var activeMountCount = 0

    private init() {}

    public func mountBegan(at path: String) {
        activeMountCount += 1
        guard assertionID == 0 else { return }
        var id: IOPMAssertionID = 0
        let reason = "\(AppInfo.displayName) transfer in progress (\(path))" as CFString
        let rc = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )
        if rc == kIOReturnSuccess {
            assertionID = id
        }
    }

    public func mountEnded() {
        activeMountCount = max(0, activeMountCount - 1)
        guard activeMountCount == 0, assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}

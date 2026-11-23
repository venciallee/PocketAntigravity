import Foundation
import AntigravityData
#if canImport(LocalAuthentication) && os(watchOS)
import LocalAuthentication
#endif

/// Enforces the security rule that approval actions on Apple Watch (`Allow`, `Proceed`, `Accept all`)
/// require the Watch to be **unlocked AND worn on the user's wrist** via watchOS
/// `LAPolicy.deviceOwnerAuthenticationWithWristDetection`.
///
/// Fails closed whenever a passcode is not configured, wrist detection is disabled, or the watch
/// has been removed from the wrist / locked.
public struct WatchWristUnlockGuard: WatchWristUnlockAuthorizing {
    public init() {}

    public func verifyUnlockedOnWrist(reason: String) async -> Bool {
        #if canImport(LocalAuthentication) && os(watchOS)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let context = LAContext()
            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithWristDetection, error: &authError) else {
                continuation.resume(returning: false)
                return
            }
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithWristDetection,
                localizedReason: reason
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
        #else
        return false
        #endif
    }
}

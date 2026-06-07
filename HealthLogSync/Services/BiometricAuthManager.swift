import LocalAuthentication

/// Wraps `LAContext` to evaluate biometric policy and expose availability.
final class BiometricAuthManager {
    static let shared = BiometricAuthManager()
    private init() {}

    private var isAuthenticating = false

    /// Whether the device supports biometric authentication (Face ID or Touch ID).
    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// The biometry type available on the device (`.faceID`, `.touchID`, `.none`).
    var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }

    /// Asks the user to authenticate. Returns the authenticated `LAContext` on success so callers
    /// can reuse it for Keychain reads without triggering a second biometric prompt.
    func authenticate(reason: String) async -> LAContext? {
        guard !isAuthenticating else { return nil }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return nil
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success ? context : nil
        } catch {
            return nil
        }
    }
}

import Foundation
import LocalAuthentication

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var sex = "male"
    @Published var phone = ""
    @Published var isRegistering = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPasswordVisible = false
    @Published var showSaveCredentialsAlert = false

    // MARK: - Biometrics

    /// Tracks whether the auto-trigger on appear has already fired.
    /// Stored on the ViewModel (a @StateObject) rather than as @State so it
    /// survives SwiftUI view-struct recreation caused by AppState republishing.
    private(set) var didAttemptBiometricAutoTrigger = false

    var isBiometricAvailable: Bool {
        BiometricAuthManager.shared.isAvailable
            && KeychainManager.shared.hasBiometricCredentials
    }

    var biometricButtonLabel: String {
        switch BiometricAuthManager.shared.biometryType {
        case .faceID: return "Войти через Face ID"
        case .touchID: return "Войти через Touch ID"
        default: return "Войти через биометрию"
        }
    }

    var biometricSystemImage: String {
        switch BiometricAuthManager.shared.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "person.badge.key"
        }
    }

    // MARK: - Manual login

    var isSubmitDisabled: Bool {
        if isLoading { return true }
        if email.isEmpty || password.isEmpty { return true }
        if isRegistering, firstName.isEmpty || lastName.isEmpty || phone.isEmpty { return true }
        return false
    }

    func submit() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if isRegistering {
                try await AuthService.shared.register(
                    firstName: firstName,
                    lastName: lastName,
                    sex: sex,
                    email: email,
                    phone: phone,
                    password: password
                )
            } else {
                try await AuthService.shared.login(email: email, password: password)
                showSaveCredentialsAlert = true
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveCredentialsForBiometrics() {
        KeychainManager.shared.saveBiometricCredentials(email: email, password: password)
    }

    // MARK: - Biometric login

    /// Returns true if biometric auth succeeded and the user was logged in.
    func loginWithBiometrics() async -> Bool {
        let reason = "Войдите в HealthLog, используя биометрию"
        guard await BiometricAuthManager.shared.authenticate(reason: reason) else {
            return false
        }
        guard let creds = KeychainManager.shared.biometricCredentials() else {
            errorMessage = "Сохранённые данные для биометрии не найдены"
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AuthService.shared.login(email: creds.email, password: creds.password)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Helpers

    func toggleMode() {
        isRegistering.toggle()
        errorMessage = nil
        isPasswordVisible = false
        // Allow biometric auto-trigger again if the user returns to the login tab.
        didAttemptBiometricAutoTrigger = false
    }

    func togglePasswordVisibility() {
        isPasswordVisible.toggle()
    }
}

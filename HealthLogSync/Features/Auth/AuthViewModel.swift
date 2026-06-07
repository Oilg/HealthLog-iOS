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

    @Published var biometricAutoLoginSucceeded = false

    init() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard BiometricAuthManager.shared.isAvailable,
                  KeychainManager.shared.hasBiometricCredentials else { return }
            // Wait for the screen to fully appear and user to orient the phone
            try? await Task.sleep(for: .milliseconds(800))
            let success = await loginWithBiometrics()
            if success { biometricAutoLoginSucceeded = true }
        }
    }

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
    }

    func togglePasswordVisibility() {
        isPasswordVisible.toggle()
    }
}

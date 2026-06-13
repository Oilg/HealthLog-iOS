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

    /// Minimum password length enforced both locally and by the backend.
    static let minimumPasswordLength = 8

    var isSubmitDisabled: Bool {
        if isLoading { return true }
        if email.isEmpty || password.isEmpty { return true }
        if isRegistering, firstName.trimmingCharacters(in: .whitespaces).isEmpty
            || lastName.trimmingCharacters(in: .whitespaces).isEmpty
            || phone.isEmpty { return true }
        return false
    }

    /// Non-nil when the password is too short during registration.
    var passwordHint: String? {
        guard isRegistering, !password.isEmpty,
              password.count < Self.minimumPasswordLength else { return nil }
        return "Минимум \(Self.minimumPasswordLength) символов"
    }

    /// Returns a localized error string if client-side validation fails, nil otherwise.
    private func localValidationError() -> String? {
        guard isRegistering else { return nil }
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)
        if trimmedFirst.isEmpty { return "Имя не может быть пустым" }
        if trimmedLast.isEmpty { return "Фамилия не может быть пустой" }
        if password.count < Self.minimumPasswordLength {
            return "Пароль должен содержать минимум \(Self.minimumPasswordLength) символов"
        }
        return nil
    }

    func submit() async -> Bool {
        if let validationError = localValidationError() {
            errorMessage = validationError
            return false
        }

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
        guard let context = await BiometricAuthManager.shared.authenticate(reason: reason) else {
            return false
        }
        guard let creds = KeychainManager.shared.biometricCredentials(context: context) else {
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

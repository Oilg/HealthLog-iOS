import Foundation

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
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleMode() {
        isRegistering.toggle()
        errorMessage = nil
    }
}

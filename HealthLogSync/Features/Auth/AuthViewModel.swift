import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isRegistering = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    func submit() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if isRegistering {
                try await AuthService.shared.register(email: email, password: password)
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

import Foundation

final class AuthService {
    static let shared = AuthService()
    private init() {}

    func login(email: String, password: String) async throws {
        let response: AuthResponse = try await APIClient.shared.request(
            path: "/api/v1/auth/login",
            method: "POST",
            body: LoginRequest(login: email, password: password),
            requiresAuth: false
        )
        saveTokens(response)
        UserDefaultsManager.shared.userEmail = response.user.email
    }

    func register(
        firstName: String,
        lastName: String,
        sex: String,
        email: String,
        phone: String,
        password: String
    ) async throws {
        let response: AuthResponse = try await APIClient.shared.request(
            path: "/api/v1/auth/register",
            method: "POST",
            body: RegisterRequest(
                firstName: firstName,
                lastName: lastName,
                sex: sex,
                email: email,
                phone: phone,
                password: password
            ),
            requiresAuth: false
        )
        saveTokens(response)
        UserDefaultsManager.shared.userEmail = response.user.email
    }

    func logout() async throws {
        _ = try? await APIClient.shared.request(
            path: "/api/v1/auth/logout",
            method: "POST",
            body: nil as String?,
            requiresAuth: true
        ) as EmptyResponse
        clearSession()
    }

    func clearSession() {
        KeychainManager.shared.deleteAll()
        UserDefaultsManager.shared.clearUserData()
    }

    var isLoggedIn: Bool {
        KeychainManager.shared.get(.accessToken) != nil
    }

    private func saveTokens(_ response: AuthResponse) {
        KeychainManager.shared.save(response.tokens.accessToken, for: .accessToken)
        KeychainManager.shared.save(response.tokens.refreshToken, for: .refreshToken)
    }
}

struct EmptyResponse: Decodable {}

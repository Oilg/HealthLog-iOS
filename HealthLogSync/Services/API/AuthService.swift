import Foundation

final class AuthService {
    static let shared = AuthService()
    private init() {}

    func login(email: String, password: String) async throws {
        let response: AuthResponse = try await APIClient.shared.request(
            path: "/api/v1/auth/login",
            method: "POST",
            body: AuthRequest(email: email, password: password),
            requiresAuth: false
        )
        saveTokens(response)
    }

    func register(email: String, password: String) async throws {
        let response: AuthResponse = try await APIClient.shared.request(
            path: "/api/v1/auth/register",
            method: "POST",
            body: RegisterRequest(email: email, password: password),
            requiresAuth: false
        )
        saveTokens(response)
        UserDefaultsManager.shared.userEmail = email
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
        KeychainManager.shared.save(response.accessToken, for: .accessToken)
        KeychainManager.shared.save(response.refreshToken, for: .refreshToken)
    }
}

struct EmptyResponse: Decodable {}

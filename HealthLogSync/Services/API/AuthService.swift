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
        password: String,
        timezone: String = TimeZone.current.identifier
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
                password: password,
                timezone: timezone
            ),
            requiresAuth: false
        )
        saveTokens(response)
        UserDefaultsManager.shared.userEmail = response.user.email
    }

    /// Updates the authenticated user's profile. Any nil field is omitted from the request body
    /// so callers can update only `timezone`, only `dateOfBirth`, or both.
    @discardableResult
    func updateProfile(timezone: String? = nil, dateOfBirth: String? = nil) async throws -> UserProfileResponse {
        try await APIClient.shared.request(
            path: "/api/v1/users/me",
            method: "PATCH",
            body: UpdateProfileRequest(timezone: timezone, dateOfBirth: dateOfBirth),
            requiresAuth: true
        )
    }

    func fetchProfile() async throws -> UserProfileResponse {
        try await APIClient.shared.request(
            path: "/api/v1/users/me",
            method: "GET",
            body: nil as String?,
            requiresAuth: true
        )
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

    func registerDeviceToken(_ token: String) async {
        _ = try? await APIClient.shared.request(
            path: "/api/v1/users/me/device-token",
            method: "PUT",
            body: DeviceTokenRequest(deviceToken: token),
            requiresAuth: true
        ) as EmptyResponse
    }

    func deleteAccount() async throws {
        _ = try await APIClient.shared.request(
            path: "/api/v1/users/me",
            method: "DELETE",
            body: nil as String?,
            requiresAuth: true
        ) as EmptyResponse
        clearSession()
    }

    func clearSession() {
        KeychainManager.shared.deleteAll()
        // clearUserData() synchronously removes the per-user DOB sync flag
        // (keyed by email) so the next authenticated account triggers a fresh upload.
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

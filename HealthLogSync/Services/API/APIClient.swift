import Foundation

enum APIClientError: Error, LocalizedError {
    case unauthorized
    case serverError(String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Сессия истекла. Войдите снова."
        case let .serverError(msg): return msg
        case .decodingError: return "Ошибка обработки данных."
        case let .networkError(err): return err.localizedDescription
        }
    }
}

extension Notification.Name {
    static let sessionDidExpire = Notification.Name("com.healthlogsync.sessionDidExpire")
}

// MARK: - APIClient

final class APIClient {
    static let shared = APIClient()

    private let baseURL: String = "https://healthlog.tech"
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true,
        postSessionExpiredOnUnauthorized: Bool = true
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIClientError.serverError("Неверный URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth {
            guard let token = KeychainManager.shared.get(.accessToken) else {
                throw APIClientError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIClientError.serverError("Нет ответа от сервера")
            }

            if http.statusCode == 401 {
                let refreshed = try await refreshTokens()
                if refreshed {
                    return try await self.request(
                        path: path,
                        method: method,
                        body: body,
                        requiresAuth: requiresAuth,
                        postSessionExpiredOnUnauthorized: postSessionExpiredOnUnauthorized
                    )
                }
                if postSessionExpiredOnUnauthorized {
                    NotificationCenter.default.post(name: .sessionDidExpire, object: nil)
                }
                throw APIClientError.unauthorized
            }

            guard (200 ..< 300).contains(http.statusCode) else {
                throw APIClientError.serverError(Self.parseErrorMessage(from: data, statusCode: http.statusCode))
            }

            // 204 No Content — decode from empty JSON object
            let bodyData = http.statusCode == 204 ? Data("{}".utf8) : data

            do {
                return try decoder.decode(T.self, from: bodyData)
            } catch {
                throw APIClientError.decodingError(error)
            }
        } catch let error as APIClientError {
            throw error
        } catch {
            throw APIClientError.networkError(error)
        }
    }

    // MARK: - Error parsing

    /// Tries to extract a human-readable message from the raw response body.
    /// Handles both `{"detail": "..."}` (FastAPI HTTPException) and
    /// `[{"type":..., "msg":..., "loc":...}]` (Pydantic validation errors).
    private static func parseErrorMessage(from data: Data, statusCode: Int) -> String {
        let decoder = JSONDecoder()

        // Try Pydantic array first
        if let items = try? decoder.decode([ValidationErrorItem].self, from: data), !items.isEmpty {
            return items
                .map { Self.localizedValidationMessage(for: $0) }
                .joined(separator: "\n")
        }

        // Try standard FastAPI detail string
        if let apiError = try? decoder.decode(APIError.self, from: data) {
            return apiError.detail
        }

        return "Ошибка сервера \(statusCode)"
    }

    /// Maps a Pydantic validation error item to a Russian user-facing string.
    private static func localizedValidationMessage(for item: ValidationErrorItem) -> String {
        let field = item.fieldName

        // Password length
        if item.type == "string_too_short" && field.contains("password") {
            let minLen = item.ctx?["min_length"]?.intValue ?? AuthViewModel.minimumPasswordLength
            return "Пароль должен содержать минимум \(minLen) символов"
        }
        if item.type == "string_too_long" && field.contains("password") {
            return "Пароль слишком длинный"
        }

        // Email
        if field.contains("email") {
            return "Некорректный формат email"
        }

        // Names
        if field.contains("first_name") {
            return "Имя не может быть пустым"
        }
        if field.contains("last_name") {
            return "Фамилия не может быть пустой"
        }

        // Phone
        if field.contains("phone") {
            return "Некорректный формат телефона"
        }

        // Fallback — return raw message without Pydantic boilerplate
        return item.msg
    }

    private func refreshTokens() async throws -> Bool {
        guard let refreshToken = KeychainManager.shared.get(.refreshToken) else { return false }
        guard let url = URL(string: baseURL + "/api/v1/auth/refresh") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RefreshRequest(refreshToken: refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            return false
        }
        let tokens = try decoder.decode(TokenResponse.self, from: data)
        KeychainManager.shared.save(tokens.accessToken, for: .accessToken)
        KeychainManager.shared.save(tokens.refreshToken, for: .refreshToken)
        return true
    }
}

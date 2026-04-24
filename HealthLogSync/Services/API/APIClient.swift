import Foundation

enum APIClientError: Error, LocalizedError {
    case unauthorized
    case serverError(String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Сессия истекла. Войдите снова."
        case .serverError(let msg): return msg
        case .decodingError: return "Ошибка обработки данных."
        case .networkError(let err): return err.localizedDescription
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL: String = "http://5.129.199.50"
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
        requiresAuth: Bool = true
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
                    return try await self.request(path: path, method: method, body: body, requiresAuth: requiresAuth)
                }
                throw APIClientError.unauthorized
            }

            guard (200..<300).contains(http.statusCode) else {
                let apiError = try? decoder.decode(APIError.self, from: data)
                throw APIClientError.serverError(apiError?.detail ?? "Ошибка сервера \(http.statusCode)")
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

    private func refreshTokens() async throws -> Bool {
        guard let refreshToken = KeychainManager.shared.get(.refreshToken) else { return false }
        guard let url = URL(string: baseURL + "/api/v1/auth/refresh") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RefreshRequest(refreshToken: refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return false
        }
        let tokens = try decoder.decode(TokenResponse.self, from: data)
        KeychainManager.shared.save(tokens.accessToken, for: .accessToken)
        KeychainManager.shared.save(tokens.refreshToken, for: .refreshToken)
        return true
    }
}

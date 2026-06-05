import CommonCrypto
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

// MARK: - Certificate Pinning Delegate

private final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    /// SHA-256 fingerprint of the server's public key (DER-encoded SubjectPublicKeyInfo)
    /// Generated with:
    ///   openssl s_client -connect 5.129.199.50:443 </dev/null 2>/dev/null \
    ///   | openssl x509 -pubkey -noout \
    ///   | openssl pkey -pubin -outform DER \
    ///   | openssl dgst -sha256 -binary | base64
    static let pinnedPublicKeyHash = "sI9OZ7s7iBAEAmi6LJGfkjXE6Zt88nSlKTjsXl3qg4k="

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract the leaf certificate's public key and compare its SHA-256 hash
        guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCertificate = certChain.first
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let publicKey = SecCertificateCopyKey(leafCertificate),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // ASN.1 header for RSA-2048 public key (SubjectPublicKeyInfo wrapper)
        let rsa2048Header: [UInt8] = [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0D, 0x06, 0x09,
            0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0F, 0x00,
        ]

        var dataToHash = Data(rsa2048Header)
        dataToHash.append(publicKeyData)

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        dataToHash.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(dataToHash.count), &hash)
        }
        let computedHash = Data(hash).base64EncodedString()

        if computedHash == CertificatePinningDelegate.pinnedPublicKeyHash {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - APIClient

final class APIClient {
    static let shared = APIClient()

    private let baseURL: String = "https://5.129.199.50"
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        let delegate = CertificatePinningDelegate()
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
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

            guard (200 ..< 300).contains(http.statusCode) else {
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
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            return false
        }
        let tokens = try decoder.decode(TokenResponse.self, from: data)
        KeychainManager.shared.save(tokens.accessToken, for: .accessToken)
        KeychainManager.shared.save(tokens.refreshToken, for: .refreshToken)
        return true
    }
}

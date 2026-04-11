import Foundation

final class AnalysisService {
    static let shared = AnalysisService()
    private init() {}

    func fetchLatest() async throws -> AnalysisReport {
        try await APIClient.shared.request(path: "/api/v1/analysis/latest")
    }

    func fetchHistory(limit: Int = 30, offset: Int = 0) async throws -> AnalysisHistoryResponse {
        try await APIClient.shared.request(
            path: "/api/v1/analysis/history?limit=\(limit)&offset=\(offset)"
        )
    }
}

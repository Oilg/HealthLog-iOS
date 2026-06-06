import Foundation

protocol AnalysisServiceProtocol {
    func fetchLatest() async throws -> AnalysisReport
    func fetchWeeklyProgress() async throws -> WeeklyProgressResponse
}

final class AnalysisService: AnalysisServiceProtocol {
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

    func fetchWeeklyProgress() async throws -> WeeklyProgressResponse {
        try await APIClient.shared.request(path: "/api/v1/analysis/weekly-progress")
    }
}

import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var latestReport: AnalysisReport?
    @Published private(set) var isLoadingReport = false
    @Published private(set) var reportError: String?

    func refresh() async {
        await loadLatestReport()
    }

    func loadLatestReport() async {
        isLoadingReport = true
        reportError = nil
        do {
            latestReport = try await AnalysisService.shared.fetchLatest()
        } catch let APIClientError.serverError(msg) where msg.contains("404") || msg.contains("не найден") {
            latestReport = nil
        } catch {
            reportError = error.localizedDescription
        }
        isLoadingReport = false
    }
}

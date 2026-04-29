import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var latestReport: AnalysisReport?
    @Published private(set) var isLoadingReport = false
    @Published private(set) var reportError: String?
    @Published private(set) var analysisInProgress = false

    private var analysisReadyObserver: NSObjectProtocol?

    init() {
        analysisReadyObserver = NotificationCenter.default.addObserver(
            forName: .analysisReady,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.analysisInProgress = false
                await self.loadLatestReport()
            }
        }
    }

    deinit {
        if let observer = analysisReadyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() async {
        analysisInProgress = false
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

    func markAnalysisInProgress() {
        analysisInProgress = true
    }
}

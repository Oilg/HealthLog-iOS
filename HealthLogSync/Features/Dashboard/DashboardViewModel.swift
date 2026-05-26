import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var latestReport: AnalysisReport?
    @Published private(set) var isLoadingReport = false
    @Published private(set) var reportError: String?
    @Published private(set) var analysisInProgress = false
    @Published private(set) var weeklyProgress: WeeklyProgressResponse?
    @Published private(set) var isLoadingWeeklyProgress = false

    private var analysisReadyObserver: NSObjectProtocol?
    private var weeklyProgressTask: Task<Void, Never>?

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
                self.weeklyProgressTask?.cancel()
                self.weeklyProgressTask = Task { await self.loadWeeklyProgress() }
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
        weeklyProgressTask?.cancel()
        weeklyProgressTask = Task { await loadWeeklyProgress() }
        await weeklyProgressTask?.value
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

    func loadWeeklyProgress() async {
        isLoadingWeeklyProgress = true
        defer { isLoadingWeeklyProgress = false }
        do {
            weeklyProgress = try await AnalysisService.shared.fetchWeeklyProgress()
        } catch {
            // Weekly progress is auxiliary — silently swallow errors so the main
            // analysis card remains usable. Preserve last successfully loaded data
            // on refresh errors; only leave nil if we never had data.
            if weeklyProgress == nil {
                weeklyProgress = nil
            }
        }
    }

    func markAnalysisInProgress() {
        analysisInProgress = true
    }
}

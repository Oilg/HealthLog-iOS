import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var latestReport: AnalysisReport?
    @Published private(set) var isLoadingReport = false
    @Published private(set) var reportError: String?
    @Published private(set) var analysisInProgress = false
    @Published private(set) var analysisTimedOut = false
    @Published private(set) var weeklyProgress: WeeklyProgressResponse?
    @Published private(set) var isLoadingWeeklyProgress = false

    private var analysisReadyObserver: NSObjectProtocol?
    private var weeklyProgressTask: Task<Void, Never>?
    private var analysisPollingTask: Task<Void, Never>?

    private let getFreshAnalysisUseCase: GetFreshAnalysisUseCase
    private let clock: Clock

    init(
        getFreshAnalysisUseCase: GetFreshAnalysisUseCase = GetFreshAnalysisUseCase(),
        clock: Clock = SystemClock()
    ) {
        self.getFreshAnalysisUseCase = getFreshAnalysisUseCase
        self.clock = clock
        analysisReadyObserver = NotificationCenter.default.addObserver(
            forName: .analysisReady,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.analysisPollingTask?.cancel()
                self.analysisPollingTask = nil
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
        analysisPollingTask?.cancel()
        weeklyProgressTask?.cancel()
    }

    func refresh() async {
        let previousTask = analysisPollingTask
        analysisPollingTask = nil
        previousTask?.cancel()
        await previousTask?.value
        analysisInProgress = false
        analysisTimedOut = false
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
        analysisTimedOut = false
        let syncStartedAt = clock.now()

        // Отменяем предыдущий polling если он ещё идёт
        analysisPollingTask?.cancel()

        analysisPollingTask = Task { @MainActor in
            let result = await getFreshAnalysisUseCase.execute(syncStartedAt: syncStartedAt)
            guard !Task.isCancelled else { return }

            switch result {
            case let .success(report):
                self.latestReport = report
                self.analysisInProgress = false
                self.analysisPollingTask = nil
                self.weeklyProgressTask?.cancel()
                self.weeklyProgressTask = Task { await self.loadWeeklyProgress() }
            case .timedOut:
                self.analysisInProgress = false
                self.analysisTimedOut = true
                self.analysisPollingTask = nil
            case .cancelled:
                break
            }
        }
    }
}

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
    private var analysisPollingTask: Task<Void, Never>?

    init() {
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
        analysisPollingTask?.cancel()
        analysisPollingTask = nil
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
        let syncStartedAt = Date()
        analysisPollingTask?.cancel()
        analysisPollingTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            let deadline = Date().addingTimeInterval(50)
            while Date() < deadline {
                guard !Task.isCancelled else { return }
                if let report = try? await AnalysisService.shared.fetchLatest(),
                   let reportDate = parseISO8601(report.analyzedAt),
                   reportDate > syncStartedAt {
                    await MainActor.run {
                        self.latestReport = report
                        self.analysisInProgress = false
                        self.analysisPollingTask = nil
                        self.weeklyProgressTask?.cancel()
                        self.weeklyProgressTask = Task { await self.loadWeeklyProgress() }
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
            }
            await MainActor.run {
                self.analysisInProgress = false
                self.analysisPollingTask = nil
            }
        }
    }

    nonisolated private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = df.date(from: string) { return date }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: string)
    }
}

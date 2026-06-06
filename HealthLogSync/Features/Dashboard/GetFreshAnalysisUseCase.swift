import Foundation

/// Результат выполнения polling-а за свежим анализом.
enum GetFreshAnalysisResult {
    case success(AnalysisReport)
    case timedOut
    case cancelled
}

/// UseCase: ожидает появления анализа свежее заданной даты.
/// Инкапсулирует весь polling-цикл, освобождая ViewModel от деталей реализации.
final class GetFreshAnalysisUseCase {
    private let analysisService: AnalysisServiceProtocol
    private let clock: Clock

    /// Время первоначального ожидания перед первым запросом (сек).
    let initialDelay: TimeInterval
    /// Максимальное время polling-а после первого запроса (сек).
    let pollingDuration: TimeInterval
    /// Интервал между запросами (сек).
    let pollingInterval: TimeInterval

    init(
        analysisService: AnalysisServiceProtocol = AnalysisService.shared,
        clock: Clock = SystemClock(),
        initialDelay: TimeInterval = 10,
        pollingDuration: TimeInterval = 50,
        pollingInterval: TimeInterval = 5
    ) {
        self.analysisService = analysisService
        self.clock = clock
        self.initialDelay = initialDelay
        self.pollingDuration = pollingDuration
        self.pollingInterval = pollingInterval
    }

    /// Запускает polling и ждёт анализа свежее `syncStartedAt`.
    func execute(syncStartedAt: Date) async -> GetFreshAnalysisResult {
        // Начальная пауза — бэкенд ещё только обрабатывает данные
        do {
            try await Task.sleep(for: .seconds(initialDelay))
        } catch is CancellationError {
            return .cancelled
        }
        guard !Task.isCancelled else { return .cancelled }

        let deadline = clock.now().addingTimeInterval(pollingDuration)

        while clock.now() < deadline {
            guard !Task.isCancelled else { return .cancelled }

            if let report = try? await analysisService.fetchLatest(),
               let reportDate = parseISO8601(report.analyzedAt),
               reportDate > syncStartedAt
            {
                return .success(report)
            }

            do {
                try await Task.sleep(for: .seconds(pollingInterval))
            } catch is CancellationError {
                return .cancelled
            }
            guard !Task.isCancelled else { return .cancelled }
        }

        return .timedOut
    }

    // MARK: - Private

    private func parseISO8601(_ string: String) -> Date? {
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

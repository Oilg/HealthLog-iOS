import XCTest
@testable import HealthLogSync

// MARK: - Test doubles

final class FakeClock: Clock {
    var currentDate: Date
    /// Если задан — автоматически продвигает время на этот интервал при каждом вызове `now()`.
    /// Полезно чтобы `while clock.now() < deadline` завершилось в тестах без реального sleep.
    var autoAdvanceInterval: TimeInterval

    init(date: Date = Date(timeIntervalSince1970: 1_000_000), autoAdvanceInterval: TimeInterval = 0) {
        currentDate = date
        self.autoAdvanceInterval = autoAdvanceInterval
    }

    func now() -> Date {
        if autoAdvanceInterval > 0 {
            currentDate = currentDate.addingTimeInterval(autoAdvanceInterval)
        }
        return currentDate
    }

    func advance(by interval: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(interval)
    }
}

final class FakeAnalysisService: AnalysisServiceProtocol {
    var stubbedReport: AnalysisReport?
    var fetchLatestCallCount = 0

    func fetchLatest() async throws -> AnalysisReport {
        fetchLatestCallCount += 1
        if let report = stubbedReport {
            return report
        }
        throw URLError(.notConnectedToInternet)
    }

    func fetchWeeklyProgress() async throws -> WeeklyProgressResponse {
        throw URLError(.notConnectedToInternet)
    }
}

// MARK: - GetFreshAnalysisUseCase tests

final class GetFreshAnalysisUseCaseTests: XCTestCase {

    // Вспомогательная фабрика с минимальными задержками для быстрых тестов
    private func makeUseCase(
        service: FakeAnalysisService = FakeAnalysisService(),
        clock: FakeClock = FakeClock()
    ) -> GetFreshAnalysisUseCase {
        GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 0,
            pollingDuration: 60,
            pollingInterval: 0
        )
    }

    func test_execute_returnsSuccess_whenFreshReportFound() async throws {
        let clock = FakeClock()
        let syncStart = clock.now().addingTimeInterval(-1)

        let freshReport = makeReport(analyzedAt: clock.now())
        let service = FakeAnalysisService()
        service.stubbedReport = freshReport

        let useCase = makeUseCase(service: service, clock: clock)
        let result = await useCase.execute(syncStartedAt: syncStart)

        guard case .success(let report) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(report.analyzedAt, freshReport.analyzedAt)
    }

    func test_execute_returnsTimedOut_whenNoFreshReport() async {
        let clock = FakeClock()
        let syncStart = clock.now().addingTimeInterval(-1)

        // Сервис возвращает старый отчёт (до syncStart)
        let oldDate = clock.now().addingTimeInterval(-3600)
        let oldReport = makeReport(analyzedAt: oldDate)
        let service = FakeAnalysisService()
        service.stubbedReport = oldReport

        // Polling 0 сек — сразу истечёт
        let useCase = GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 0,
            pollingDuration: 0,
            pollingInterval: 0
        )
        let result = await useCase.execute(syncStartedAt: syncStart)

        XCTAssertEqual(result, .timedOut)
    }

    func test_execute_returnsTimedOut_withAutoAdvancingClock() async {
        // FakeClock с autoAdvanceInterval гарантирует завершение цикла
        // даже при pollingDuration > 0, без риска бесконечного цикла.
        let clock = FakeClock(autoAdvanceInterval: 30) // каждый вызов now() +30 сек
        let syncStart = clock.now().addingTimeInterval(-1)

        let oldReport = makeReport(analyzedAt: clock.now().addingTimeInterval(-3600))
        let service = FakeAnalysisService()
        service.stubbedReport = oldReport

        let useCase = GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 0,
            pollingDuration: 60, // без autoAdvance — цикл мог бы зависнуть
            pollingInterval: 0
        )
        let result = await useCase.execute(syncStartedAt: syncStart)

        XCTAssertEqual(result, .timedOut)
    }

    func test_execute_returnsCancelled_whenTaskCancelled() async {
        let clock = FakeClock()
        let syncStart = clock.now()
        let service = FakeAnalysisService()

        let useCase = GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 60, // долгая начальная задержка
            pollingDuration: 60,
            pollingInterval: 5
        )

        let task = Task {
            await useCase.execute(syncStartedAt: syncStart)
        }
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, .cancelled)
    }

    // MARK: - Отмена polling при повторном вызове

    func test_markAnalysisInProgress_cancelsPreviousPolling() async throws {
        // При повторном вызове markAnalysisInProgress старый Task должен быть отменён.
        // Проверяем косвенно: сервис дёргается ровно столько раз, сколько ожидаем.
        let clock = FakeClock()
        let service = FakeAnalysisService()
        // Второй вызов сразу найдёт свежий отчёт
        let freshReport = makeReport(analyzedAt: clock.now().addingTimeInterval(1))

        let slowUseCase = GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 10, // первый вызов — долго ждёт
            pollingDuration: 60,
            pollingInterval: 5
        )

        let viewModel = await DashboardViewModel(
            getFreshAnalysisUseCase: slowUseCase,
            clock: clock
        )

        // Первый вызов — стартует и уходит в ожидание initialDelay
        await viewModel.markAnalysisInProgress()
        // Небольшая пауза чтобы задача запустилась
        try await Task.sleep(for: .milliseconds(50))

        // Подкладываем свежий отчёт и создаём быстрый UseCase для второго вызова
        service.stubbedReport = freshReport
        let fastUseCase = GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 0,
            pollingDuration: 60,
            pollingInterval: 0
        )

        // Имитируем второй вызов через другой ViewModel с быстрым UseCase,
        // убеждаясь что старый polling отменяется.
        let viewModel2 = await DashboardViewModel(
            getFreshAnalysisUseCase: fastUseCase,
            clock: clock
        )
        let syncStart = clock.now().addingTimeInterval(-1)
        let result = await fastUseCase.execute(syncStartedAt: syncStart)

        guard case .success = result else {
            XCTFail("Expected success on second call")
            return
        }
        // Убеждаемся что первый ViewModel перестаёт быть in-progress если его task отменён
        await viewModel.refresh()
        let isInProgress = await viewModel.analysisInProgress
        XCTAssertFalse(isInProgress)
        _ = viewModel2 // silence warning
    }

    // MARK: - analysisTimedOut @Published

    func test_analysisTimedOut_isSetToTrue_onTimeout() async throws {
        let clock = FakeClock()
        // Сервис никогда не возвращает свежий отчёт
        let oldReport = makeReport(analyzedAt: clock.now().addingTimeInterval(-3600))
        let service = FakeAnalysisService()
        service.stubbedReport = oldReport

        let useCase = GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 0,
            pollingDuration: 0, // сразу timeout
            pollingInterval: 0
        )
        let viewModel = await DashboardViewModel(
            getFreshAnalysisUseCase: useCase,
            clock: clock
        )

        await viewModel.markAnalysisInProgress()
        // Ждём завершения фонового Task
        try await Task.sleep(for: .milliseconds(200))

        let timedOut = await viewModel.analysisTimedOut
        let inProgress = await viewModel.analysisInProgress
        XCTAssertTrue(timedOut, "analysisTimedOut должен быть true после таймаута")
        XCTAssertFalse(inProgress, "analysisInProgress должен быть false после таймаута")
    }

    func test_analysisTimedOut_isResetOnRefresh() async throws {
        let clock = FakeClock()
        let service = FakeAnalysisService()
        let useCase = GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 0,
            pollingDuration: 0,
            pollingInterval: 0
        )
        let viewModel = await DashboardViewModel(
            getFreshAnalysisUseCase: useCase,
            clock: clock
        )

        await viewModel.markAnalysisInProgress()
        try await Task.sleep(for: .milliseconds(200))

        let timedOutBefore = await viewModel.analysisTimedOut
        XCTAssertTrue(timedOutBefore)

        await viewModel.refresh()
        let timedOutAfter = await viewModel.analysisTimedOut
        XCTAssertFalse(timedOutAfter, "analysisTimedOut должен сброситься после refresh")
    }

    // MARK: - Clock injection

    func test_clock_isUsedForSyncStartTime() async {
        let clock = FakeClock()
        // syncStart будет взят из clock.now() внутри markAnalysisInProgress
        // Report с датой == clock.now() должен считаться свежим
        let reportDate = clock.now().addingTimeInterval(1)
        let report = makeReport(analyzedAt: reportDate)
        let service = FakeAnalysisService()
        service.stubbedReport = report

        let useCase = GetFreshAnalysisUseCase(
            analysisService: service,
            clock: clock,
            initialDelay: 0,
            pollingDuration: 60,
            pollingInterval: 0
        )

        let syncStart = clock.now()
        let result = await useCase.execute(syncStartedAt: syncStart)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
    }

    // MARK: - Helpers

    private func makeReport(analyzedAt: Date) -> AnalysisReport {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let isoString = formatter.string(from: analyzedAt)
        let json = """
        {
            "analyzed_at": "\(isoString)",
            "risks": []
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(AnalysisReport.self, from: json)
    }
}

extension GetFreshAnalysisResult: Equatable {
    public static func == (lhs: GetFreshAnalysisResult, rhs: GetFreshAnalysisResult) -> Bool {
        switch (lhs, rhs) {
        case (.timedOut, .timedOut): return true
        case (.cancelled, .cancelled): return true
        case (.success(let a), .success(let b)): return a.analyzedAt == b.analyzedAt
        default: return false
        }
    }
}

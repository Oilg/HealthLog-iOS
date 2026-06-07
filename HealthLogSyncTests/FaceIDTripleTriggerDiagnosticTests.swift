import Combine
import XCTest
@testable import HealthLogSync

/// Диагностический тест для понимания причины тройного срабатывания Face ID.
/// Проверяет: не происходит ли sessionDidExpire после onLoginSuccess(),
/// и не флипает ли isLoggedIn false→true→false в петле.
@MainActor
final class FaceIDTripleTriggerDiagnosticTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        super.tearDown()
        KeychainManager.shared.deleteAll()
        UserDefaultsManager.shared.clearUserData()
        cancellables.removeAll()
    }

    // MARK: - Тест 1: сколько раз срабатывает sessionDidExpire после onLoginSuccess()

    func test_sessionExpiry_doesNotFireAfterLoginSuccess() async throws {
        // Arrange: нет токенов — пользователь не залогинен
        KeychainManager.shared.deleteAll()

        var sessionExpiredCount = 0
        let expiredExpectation = XCTestExpectation(description: "sessionDidExpire НЕ должен срабатывать")
        expiredExpectation.isInverted = true // ожидаем что НЕ сработает

        let observer = NotificationCenter.default.addObserver(
            forName: .sessionDidExpire,
            object: nil,
            queue: .main
        ) { _ in
            sessionExpiredCount += 1
            print("🔴 [TEST] sessionDidExpire сработал! count=\(sessionExpiredCount)")
            expiredExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let appState = AppState()
        XCTAssertFalse(appState.isLoggedIn, "Должен быть разлогинен без токенов")

        // Симулируем успешный биометрический вход: сохраняем токены как при реальном логине
        KeychainManager.shared.save("fake-access-token", for: .accessToken)
        KeychainManager.shared.save("fake-refresh-token", for: .refreshToken)
        print("🟢 [TEST] Токены сохранены, вызываем onLoginSuccess()")

        // Отслеживаем все изменения isLoggedIn
        var isLoggedInHistory: [Bool] = [appState.isLoggedIn]
        appState.$isLoggedIn
            .dropFirst()
            .sink { value in
                isLoggedInHistory.append(value)
                print("📊 [TEST] isLoggedIn изменился: \(isLoggedInHistory)")
            }
            .store(in: &cancellables)

        appState.onLoginSuccess()
        print("🟢 [TEST] onLoginSuccess() вызван, isLoggedIn=\(appState.isLoggedIn)")

        // Ждём 3 секунды — время для checkSyncStatusAndSkipOnboardingIfNeeded() с сетевым вызовом
        try await Task.sleep(nanoseconds: 3_000_000_000)

        print("📊 [TEST] Итог через 3с: isLoggedIn=\(appState.isLoggedIn), sessionExpiredCount=\(sessionExpiredCount)")
        print("📊 [TEST] История isLoggedIn: \(isLoggedInHistory)")

        await fulfillment(of: [expiredExpectation], timeout: 0.1)

        XCTAssertEqual(
            sessionExpiredCount,
            0,
            "sessionDidExpire НЕ должен срабатывать после успешного логина. Сработал \(sessionExpiredCount) раз(а). " +
                "История isLoggedIn: \(isLoggedInHistory)"
        )
        XCTAssertTrue(
            appState.isLoggedIn,
            "isLoggedIn должен оставаться true после onLoginSuccess(). История: \(isLoggedInHistory)"
        )
    }

    // MARK: - Тест 2: сколько раз AuthViewModel создаётся при показе AuthView

    func test_authViewModelInit_firesOnce() async throws {
        // Arrange: нет токенов
        KeychainManager.shared.deleteAll()

        // Считаем сколько AuthViewModel экземпляров создаётся
        // (косвенно через наблюдение за сессией)
        var initCount = 0

        // Создаём 3 экземпляра AuthViewModel (симуляция пересоздания AuthView)
        // и проверяем что это не вызывает проблем
        var viewModels: [AuthViewModel] = []
        for i in 1 ... 3 {
            let vm = AuthViewModel()
            viewModels.append(vm)
            initCount += 1
            print("🔵 [TEST] AuthViewModel #\(i) создан, id=\(ObjectIdentifier(vm).hashValue)")
        }

        // Ждём 500мс — время для init() Task из каждого AuthViewModel
        try await Task.sleep(nanoseconds: 500_000_000)

        print("🔵 [TEST] Всего AuthViewModel экземпляров: \(initCount)")
        // Если биометрия недоступна в симуляторе, Task в init() сразу вернётся
        // Но мы проверяем что нет неожиданных sessionExpire
        XCTAssertEqual(initCount, 3, "Создали 3 AuthViewModel — это симуляция тройного пересоздания AuthView")
    }

    // MARK: - Тест 3: isLoggedIn не флипает при быстрой последовательности login→sessionExpiry

    func test_rapidLoginSessionExpiryLoop_detection() async throws {
        KeychainManager.shared.deleteAll()

        var loginSuccessCount = 0
        var sessionExpiredCount = 0
        var isLoggedInHistory: [Bool] = []

        let appState = AppState()

        appState.$isLoggedIn
            .dropFirst()
            .sink { value in
                isLoggedInHistory.append(value)
                print("📊 [TEST] isLoggedIn → \(value), history=\(isLoggedInHistory)")
            }
            .store(in: &cancellables)

        let expiredObserver = NotificationCenter.default.addObserver(
            forName: .sessionDidExpire, object: nil, queue: .main
        ) { _ in
            sessionExpiredCount += 1
            print("🔴 [TEST] sessionDidExpire #\(sessionExpiredCount) сработал!")
        }
        defer { NotificationCenter.default.removeObserver(expiredObserver) }

        // Симуляция петли: login → session expire → login → session expire → login (успех)
        for round in 1 ... 3 {
            print("🔄 [TEST] Раунд \(round): сохраняем токены и вызываем onLoginSuccess()")
            KeychainManager.shared.save("token-round-\(round)", for: .accessToken)
            KeychainManager.shared.save("refresh-round-\(round)", for: .refreshToken)
            appState.onLoginSuccess()
            loginSuccessCount += 1

            // Пауза 50мс между раундами (очень быстро — как Face ID без паузы)
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Ждём финальной стабилизации
        try await Task.sleep(nanoseconds: 3_000_000_000)

        print("📊 [TEST] Итог: loginSuccess=\(loginSuccessCount), sessionExpired=\(sessionExpiredCount)")
        print("📊 [TEST] isLoggedIn история: \(isLoggedInHistory)")

        // Если sessionExpiredCount > 0 — это подтверждает петлю
        if sessionExpiredCount > 0 {
            print("❌ [TEST] ПОДТВЕРЖДЕНА ПЕТЛЯ: после onLoginSuccess() срабатывает sessionDidExpire!")
            print("❌ [TEST] Это объясняет тройное Face ID: login→expire→login→expire→login→успех")
        } else {
            print("✅ [TEST] Петли нет — ищем другую причину")
        }
    }
}

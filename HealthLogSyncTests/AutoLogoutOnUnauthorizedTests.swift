import XCTest
@testable import HealthLogSync

/// Tests that posting `.sessionDidExpire` triggers session cleanup in AppState.
@MainActor
final class AutoLogoutOnUnauthorizedTests: XCTestCase {
    // MARK: - Helpers

    /// Seeds both Keychain tokens so we can assert they are removed.
    private func seedTokens() {
        KeychainManager.shared.save("access-token-value", for: .accessToken)
        KeychainManager.shared.save("refresh-token-value", for: .refreshToken)
    }

    override func tearDown() {
        super.tearDown()
        // Clean up any leftover keychain entries between tests.
        KeychainManager.shared.deleteAll()
    }

    // MARK: - Tests

    func test_sessionDidExpire_notification_clearsAccessToken() async throws {
        seedTokens()
        let appState = AppState()

        NotificationCenter.default.post(name: .sessionDidExpire, object: nil)

        // Give the MainActor task a chance to run.
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(
            KeychainManager.shared.get(.accessToken),
            "Access token must be removed from Keychain after session expiry"
        )
    }

    func test_sessionDidExpire_notification_clearsRefreshToken() async throws {
        seedTokens()
        let appState = AppState()

        NotificationCenter.default.post(name: .sessionDidExpire, object: nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(
            KeychainManager.shared.get(.refreshToken),
            "Refresh token must be removed from Keychain after session expiry"
        )
    }

    func test_sessionDidExpire_notification_setsIsLoggedInFalse() async throws {
        seedTokens()
        let appState = AppState()
        // isLoggedIn reads from Keychain — seeding tokens means it starts true.
        XCTAssertTrue(appState.isLoggedIn, "Precondition: isLoggedIn should be true when tokens exist")

        NotificationCenter.default.post(name: .sessionDidExpire, object: nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(appState.isLoggedIn, "isLoggedIn must be false after session expiry notification")
    }

    func test_sessionDidExpire_notification_resetsInitialSyncCompleted() async throws {
        seedTokens()
        UserDefaultsManager.shared.initialSyncCompleted = true
        let appState = AppState()

        NotificationCenter.default.post(name: .sessionDidExpire, object: nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(
            appState.initialSyncCompleted,
            "initialSyncCompleted must be reset after session expiry"
        )
        // Clean up
        UserDefaultsManager.shared.initialSyncCompleted = false
    }
}

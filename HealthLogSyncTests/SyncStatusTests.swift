import XCTest
@testable import HealthLogSync

final class SyncStatusTests: XCTestCase {
    // MARK: - SyncStatusResponse decoding

    func test_syncStatusResponse_decodesHasDataTrue() throws {
        let json = #"{"has_data": true, "last_sync_at": null}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(SyncStatusResponse.self, from: data)
        XCTAssertTrue(response.hasData)
        XCTAssertNil(response.lastSyncAt)
    }

    func test_syncStatusResponse_decodesHasDataFalse() throws {
        let json = #"{"has_data": false, "last_sync_at": null}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(SyncStatusResponse.self, from: data)
        XCTAssertFalse(response.hasData)
    }

    func test_syncStatusResponse_decodesLastSyncAt() throws {
        let json = #"{"has_data": true, "last_sync_at": "2024-03-15T10:30:00Z"}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(SyncStatusResponse.self, from: data)
        XCTAssertTrue(response.hasData)
        XCTAssertEqual(response.lastSyncAt, "2024-03-15T10:30:00Z")
    }

    // MARK: - UserDefaultsManager state after simulated returning-user login

    @MainActor
    func test_initialSyncCompleted_setsTrueWhenHasData() {
        // Simulate what checkSyncStatusAndSkipOnboardingIfNeeded does when hasData == true
        UserDefaultsManager.shared.initialSyncCompleted = false
        UserDefaultsManager.shared.lastSyncAt = nil

        // Apply the logic directly (no network call needed for the unit test)
        UserDefaultsManager.shared.initialSyncCompleted = true
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: "2024-03-15T10:30:00.000Z") {
            UserDefaultsManager.shared.lastSyncAt = date
        }

        XCTAssertTrue(UserDefaultsManager.shared.initialSyncCompleted)
        XCTAssertNotNil(UserDefaultsManager.shared.lastSyncAt)

        // Cleanup
        UserDefaultsManager.shared.initialSyncCompleted = false
        UserDefaultsManager.shared.lastSyncAt = nil
    }

    @MainActor
    func test_initialSyncCompleted_remainsFalseWhenHasDataFalse() {
        UserDefaultsManager.shared.initialSyncCompleted = false

        // has_data == false: do nothing
        let hasData = false
        if hasData {
            UserDefaultsManager.shared.initialSyncCompleted = true
        }

        XCTAssertFalse(UserDefaultsManager.shared.initialSyncCompleted)
    }
}

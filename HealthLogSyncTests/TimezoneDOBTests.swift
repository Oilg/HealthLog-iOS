import XCTest
@testable import HealthLogSync

/// Tests covering the timezone-on-register and date-of-birth-from-HealthKit flows
/// added to the iOS client to match the new backend contract:
///   - POST /api/v1/auth/register accepts `timezone` (IANA identifier)
///   - PATCH /api/v1/users/me accepts `timezone` and `date_of_birth`
///   - Pushes with `data.action == "open_profile"` route to the Settings screen
@MainActor
final class TimezoneDOBTests: XCTestCase {
    // MARK: - RegisterRequest serialization

    /// `RegisterRequest` must serialize `timezone` under the `timezone` JSON key
    /// because the backend expects exactly that field name.
    func test_registerRequest_encodesTimezone() throws {
        let request = RegisterRequest(
            firstName: "A",
            lastName: "B",
            sex: "male",
            email: "a@b.c",
            phone: "+1",
            password: "pw",
            timezone: "Europe/Moscow"
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["timezone"] as? String, "Europe/Moscow")
        XCTAssertEqual(json["first_name"] as? String, "A")
        XCTAssertEqual(json["last_name"] as? String, "B")
    }

    /// The default for the auth flow uses the current system timezone identifier —
    /// must be a non-empty IANA-style string so the backend does not reject it.
    func test_registerRequest_systemTimezoneIdentifierIsNonEmpty() {
        let identifier = TimeZone.current.identifier
        XCTAssertFalse(identifier.isEmpty)
        // IANA identifiers always contain a region or are `UTC`.
        XCTAssertTrue(identifier.contains("/") || identifier == "UTC" || identifier == "GMT")
    }

    // MARK: - UpdateProfileRequest serialization

    /// When both fields are provided the request body must include both with the
    /// snake_case keys the backend expects.
    func test_updateProfileRequest_includesBothFields() throws {
        let request = UpdateProfileRequest(timezone: "Europe/Moscow", dateOfBirth: "1990-05-15")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["timezone"] as? String, "Europe/Moscow")
        XCTAssertEqual(json["date_of_birth"] as? String, "1990-05-15")
    }

    /// nil fields must be omitted from the JSON body — sending `null` for
    /// timezone would clear the value server-side. The backend treats absent
    /// fields as "leave unchanged".
    func test_updateProfileRequest_omitsNilFields() throws {
        let request = UpdateProfileRequest(timezone: nil, dateOfBirth: "1990-05-15")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["timezone"])
        XCTAssertEqual(json["date_of_birth"] as? String, "1990-05-15")
    }

    func test_updateProfileRequest_omitsAllNilFields() throws {
        let request = UpdateProfileRequest(timezone: nil, dateOfBirth: nil)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json.isEmpty)
    }

    // MARK: - UserProfileResponse decoding

    func test_userProfileResponse_decodesAllFields() throws {
        let json = Data(#"{"email": "a@b.c", "timezone": "Europe/Moscow", "date_of_birth": "1990-05-15"}"#.utf8)
        let profile = try JSONDecoder().decode(UserProfileResponse.self, from: json)
        XCTAssertEqual(profile.email, "a@b.c")
        XCTAssertEqual(profile.timezone, "Europe/Moscow")
        XCTAssertEqual(profile.dateOfBirth, "1990-05-15")
    }

    func test_userProfileResponse_tolerates_nullDOB() throws {
        let json = Data(#"{"email": "a@b.c", "timezone": null, "date_of_birth": null}"#.utf8)
        let profile = try JSONDecoder().decode(UserProfileResponse.self, from: json)
        XCTAssertEqual(profile.email, "a@b.c")
        XCTAssertNil(profile.timezone)
        XCTAssertNil(profile.dateOfBirth)
    }

    // MARK: - ProfileSyncService DOB formatting

    func test_formatISODate_padsMonthAndDay() {
        var components = DateComponents()
        components.year = 1990
        components.month = 5
        components.day = 7
        XCTAssertEqual(ProfileSyncService.formatISODate(from: components), "1990-05-07")
    }

    func test_formatISODate_handlesFourDigitYear() {
        var components = DateComponents()
        components.year = 2001
        components.month = 12
        components.day = 31
        XCTAssertEqual(ProfileSyncService.formatISODate(from: components), "2001-12-31")
    }

    func test_formatISODate_returnsNilWhenAnyComponentMissing() {
        var components = DateComponents()
        components.year = 1990
        components.month = 5
        // day missing
        XCTAssertNil(ProfileSyncService.formatISODate(from: components))
    }

    // MARK: - ProfileSyncService.fetchAndSyncDOB

    /// When HealthKit returns nil (DOB not set or HK unavailable) we must NOT
    /// call updateProfile and must NOT mark the sync flag complete (so we retry
    /// next launch in case the user fills DOB in the Health app later).
    func test_fetchAndSyncDOB_skipsWhenHealthKitReturnsNil() async {
        let defaults = makeIsolatedDefaults()
        let healthKit = StubHealthKitDOBProvider(components: nil)
        let auth = SpyProfileUpdater()
        let service = ProfileSyncService(healthKit: healthKit, authService: auth, defaults: defaults)

        let synced = await service.fetchAndSyncDOB()

        XCTAssertFalse(synced)
        XCTAssertEqual(auth.callCount, 0, "updateProfile must not be called when DOB unavailable")
        XCTAssertFalse(service.hasSyncedDOB, "sync flag must not be set on skip")
    }

    /// Happy path: HealthKit yields DOB → PATCH /users/me is called with
    /// ISO date → flag is set so subsequent launches do not re-sync.
    func test_fetchAndSyncDOB_callsUpdateProfileAndSetsFlag() async {
        let defaults = makeIsolatedDefaults()
        var components = DateComponents()
        components.year = 1990
        components.month = 5
        components.day = 15
        let healthKit = StubHealthKitDOBProvider(components: components)
        let auth = SpyProfileUpdater()
        let service = ProfileSyncService(healthKit: healthKit, authService: auth, defaults: defaults)

        let synced = await service.fetchAndSyncDOB()

        XCTAssertTrue(synced)
        XCTAssertEqual(auth.callCount, 1)
        XCTAssertNil(auth.lastTimezone, "timezone is not pushed by the auto-sync path")
        XCTAssertEqual(auth.lastDateOfBirth, "1990-05-15")
        XCTAssertTrue(service.hasSyncedDOB)
    }

    /// Backend failure must keep the flag unset so the next launch retries.
    func test_fetchAndSyncDOB_keepsFlagUnsetOnBackendFailure() async {
        let defaults = makeIsolatedDefaults()
        var components = DateComponents()
        components.year = 1990
        components.month = 5
        components.day = 15
        let healthKit = StubHealthKitDOBProvider(components: components)
        let auth = SpyProfileUpdater(throwError: TestError.network)
        let service = ProfileSyncService(healthKit: healthKit, authService: auth, defaults: defaults)

        let synced = await service.fetchAndSyncDOB()

        XCTAssertFalse(synced)
        XCTAssertEqual(auth.callCount, 1)
        XCTAssertFalse(service.hasSyncedDOB, "flag must remain unset so we retry next launch")
    }

    /// Once flagged as synced, repeated calls must be no-ops — protects the
    /// backend from spam on every app launch / initial-sync completion.
    func test_fetchAndSyncDOB_isNoOpAfterFirstSuccess() async {
        let defaults = makeIsolatedDefaults()
        var components = DateComponents()
        components.year = 1990
        components.month = 5
        components.day = 15
        let healthKit = StubHealthKitDOBProvider(components: components)
        let auth = SpyProfileUpdater()
        let service = ProfileSyncService(healthKit: healthKit, authService: auth, defaults: defaults)

        _ = await service.fetchAndSyncDOB()
        _ = await service.fetchAndSyncDOB()
        _ = await service.fetchAndSyncDOB()

        XCTAssertEqual(auth.callCount, 1, "subsequent calls must not hit the backend")
    }

    /// DOB components with all nil fields (Health app blank state) must be treated
    /// as "no DOB available" — no PATCH, no flag.
    func test_fetchAndSyncDOB_skipsWhenComponentsBlank() async {
        let defaults = makeIsolatedDefaults()
        let blank = DateComponents() // all nil
        let healthKit = StubHealthKitDOBProvider(components: blank)
        let auth = SpyProfileUpdater()
        let service = ProfileSyncService(healthKit: healthKit, authService: auth, defaults: defaults)

        // Stub returns the components but ProfileSyncService delegates to the
        // provider — here we pre-validate by using HealthKitManager.fetchDateOfBirth
        // semantics: blank components should NOT reach the formatter. We approximate
        // by giving the formatter a blank set and expecting nil.
        XCTAssertNil(ProfileSyncService.formatISODate(from: blank))
        _ = await service.fetchAndSyncDOB()
        XCTAssertEqual(auth.callCount, 0)
    }

    // MARK: - Push action=open_profile

    func test_extractAction_readsTopLevelAction() {
        let userInfo: [AnyHashable: Any] = ["action": "open_profile"]
        XCTAssertEqual(AppDelegate.extractAction(from: userInfo), "open_profile")
    }

    func test_extractAction_readsNestedDataAction() {
        let userInfo: [AnyHashable: Any] = ["data": ["action": "open_profile"]]
        XCTAssertEqual(AppDelegate.extractAction(from: userInfo), "open_profile")
    }

    func test_extractAction_returnsNilWhenAbsent() {
        let userInfo: [AnyHashable: Any] = ["type": "analysis_ready"]
        XCTAssertNil(AppDelegate.extractAction(from: userInfo))
    }

    /// MainTabView listens on `Notification.Name.openProfile`. The notification name
    /// must be a stable constant — assert it does not change unexpectedly so any
    /// rename also updates the listener.
    func test_openProfileNotificationName_isStable() {
        XCTAssertEqual(Notification.Name.openProfile.rawValue, "com.healthlogsync.openProfile")
    }

    /// Posting `.openProfile` must reach subscribers — sanity check for the
    /// notification-based routing used by MainTabView.
    func test_openProfileNotification_isDeliveredToObservers() {
        let expectation = XCTestExpectation(description: "openProfile delivered")
        let observer = NotificationCenter.default.addObserver(
            forName: .openProfile,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationCenter.default.post(name: .openProfile, object: nil)
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Test doubles

private enum TestError: Error {
    case network
}

private final class StubHealthKitDOBProvider: HealthKitDOBProvider {
    let components: DateComponents?
    init(components: DateComponents?) {
        self.components = components
    }

    func fetchDateOfBirth() -> DateComponents? {
        components
    }
}

/// Test spy that records updateProfile calls. Marked `@unchecked Sendable`
/// because tests call it serially on the @MainActor and the unchecked claim
/// is fine for a controlled test environment.
private final class SpyProfileUpdater: ProfileUpdating, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastTimezone: String?
    private(set) var lastDateOfBirth: String?
    private let throwError: Error?

    init(throwError: Error? = nil) {
        self.throwError = throwError
    }

    func updateProfile(timezone: String?, dateOfBirth: String?) async throws -> UserProfileResponse {
        callCount += 1
        lastTimezone = timezone
        lastDateOfBirth = dateOfBirth
        if let throwError { throw throwError }
        return UserProfileResponse(email: "test@x.y", timezone: timezone, dateOfBirth: dateOfBirth)
    }
}

private func makeIsolatedDefaults() -> UserDefaults {
    // Use a fresh suite per test so flag state does not leak between tests
    // (and does not pollute the real standard defaults).
    let suiteName = "TimezoneDOBTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

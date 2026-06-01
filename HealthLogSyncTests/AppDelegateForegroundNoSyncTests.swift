import XCTest
@testable import HealthLogSync

/// Regression tests for the "sync on every app open" bug.
///
/// Before the fix, `AppDelegate.applicationWillEnterForeground` kicked off
/// `SyncManager.runDeltaSync()` and `application(_:didFinishLaunchingWithOptions:)`
/// wired `HealthKitManager.enableBackgroundDeliveryAndStartObservers` so that
/// any new HealthKit sample (e.g. from the Apple Watch) immediately triggered
/// a sync. The combined effect was that the backend ran a full sync + analysis
/// many times per day instead of the contracted single daily window at 07:00 UTC.
///
/// The fix removes both paths. The only legitimate sync triggers are:
///   - `BGProcessingTask` scheduled by `BackgroundTaskManager` (daily at 10:00
///     local time, lining up with the 07:00 UTC backend window for Moscow users).
///   - Silent APNs push from the server (handled in `runSilentPushSync`).
///
/// These tests pin the new contract: foregrounding the app must not move the
/// `SyncManager` state away from `.idle`, and `applicationWillEnterForeground`
/// must restrict its work to re-scheduling the daily BG task.
@MainActor
final class AppDelegateForegroundNoSyncTests: XCTestCase {
    private var savedLastSyncAt: Date?

    override func setUp() {
        super.setUp()
        savedLastSyncAt = UserDefaultsManager.shared.lastSyncAt
        SyncManager.shared.resetState()
    }

    override func tearDown() {
        UserDefaultsManager.shared.lastSyncAt = savedLastSyncAt
        SyncManager.shared.resetState()
        super.tearDown()
    }

    /// `applicationWillEnterForeground` must not start a sync. After the call
    /// the manager must still be `.idle` and `isSyncing` must be `false`.
    func test_applicationWillEnterForeground_doesNotStartSync() {
        let delegate = AppDelegate()
        let manager = SyncManager.shared

        XCTAssertEqual(manager.state, .idle, "precondition")
        XCTAssertFalse(manager.isSyncing, "precondition")

        delegate.applicationWillEnterForeground(UIApplication.shared)

        XCTAssertEqual(
            manager.state,
            .idle,
            "Foregrounding the app must not advance SyncManager state — sync runs only on the daily BG task or silent push."
        )
        XCTAssertFalse(
            manager.isSyncing,
            "Foregrounding the app must not set isSyncing — no sync should be in flight."
        )
    }

    /// `applicationWillEnterForeground` must not advance `lastSyncAt`. The
    /// cursor is owned exclusively by `SyncService.uploadRecords()` and must
    /// remain pinned to its previous value across foreground transitions.
    func test_applicationWillEnterForeground_doesNotAdvanceLastSyncAt() {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        UserDefaultsManager.shared.lastSyncAt = anchor

        let delegate = AppDelegate()
        delegate.applicationWillEnterForeground(UIApplication.shared)

        XCTAssertEqual(
            UserDefaultsManager.shared.lastSyncAt,
            anchor,
            "Foregrounding must not touch lastSyncAt — only a successful sync advances it."
        )
    }

    /// `application(_:didFinishLaunchingWithOptions:)` must not start a sync.
    /// Launch only registers BG tasks, schedules the daily sync, and requests
    /// notification permission — no HealthKit fetch, no upload.
    func test_didFinishLaunching_doesNotStartSync() {
        let delegate = AppDelegate()
        let manager = SyncManager.shared

        XCTAssertEqual(manager.state, .idle, "precondition")

        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertEqual(
            manager.state,
            .idle,
            "App launch must not start a sync — sync runs only on the daily BG task or silent push."
        )
        XCTAssertFalse(manager.isSyncing, "App launch must not set isSyncing.")
    }

    /// `applicationDidEnterBackground` must also not start a sync — it only
    /// re-schedules the daily BG task so the OS keeps the assertion warm.
    func test_applicationDidEnterBackground_doesNotStartSync() {
        let delegate = AppDelegate()
        let manager = SyncManager.shared

        XCTAssertEqual(manager.state, .idle, "precondition")

        delegate.applicationDidEnterBackground(UIApplication.shared)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(manager.isSyncing)
    }

    /// `applicationWillEnterForeground` must not cancel an already-scheduled
    /// BGProcessingTask. Before the fix, calling `scheduleDailySync()` from
    /// `applicationWillEnterForeground` would call
    /// `BGTaskScheduler.cancel(taskRequestWithIdentifier:)` and then submit a new
    /// request for the *next* 10:00 — if the user opened the app after 10:00 the
    /// already-queued daily sync was discarded and rescheduled for tomorrow.
    ///
    /// `scheduleDailySyncIfNeeded()` reads the `dailySyncScheduled` UserDefaults
    /// flag and returns early without touching BGTaskScheduler when a request is
    /// already pending. This test verifies that the flag is preserved (stays `true`)
    /// across a foreground transition so the existing request is not replaced.
    func test_applicationWillEnterForeground_preservesAlreadyScheduledBGTask() {
        let scheduledKey = "com.healthlogsync.dailySyncScheduled"
        let previousValue = UserDefaults.standard.bool(forKey: scheduledKey)
        defer { UserDefaults.standard.set(previousValue, forKey: scheduledKey) }

        // Simulate a BGProcessingTask already being scheduled (flag set by BackgroundTaskManager
        // after a successful BGTaskScheduler.submit() call).
        UserDefaults.standard.set(true, forKey: scheduledKey)

        let delegate = AppDelegate()
        delegate.applicationWillEnterForeground(UIApplication.shared)

        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: scheduledKey),
            "applicationWillEnterForeground must not clear the dailySyncScheduled flag — " +
                "doing so would cause scheduleDailySync() to cancel and replace the pending BGProcessingTask."
        )
    }

    /// `applicationDidBecomeActive` must not start a sync.
    /// Note: the badge-clearing side-effect (`setBadgeCount(0)`) cannot be
    /// verified here without injecting a mock `UNUserNotificationCenter`.
    func test_applicationDidBecomeActive_doesNotStartSync() {
        let delegate = AppDelegate()
        let manager = SyncManager.shared

        XCTAssertEqual(manager.state, .idle, "precondition")
        XCTAssertFalse(manager.isSyncing, "precondition")

        delegate.applicationDidBecomeActive(UIApplication.shared)

        XCTAssertEqual(
            manager.state,
            .idle,
            "Becoming active must not advance SyncManager state."
        )
        XCTAssertFalse(
            manager.isSyncing,
            "Becoming active must not set isSyncing."
        )
    }
}

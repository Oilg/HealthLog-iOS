import XCTest
@testable import HealthLogSync

// MARK: - Fix 1 (HIGH): DeferredDeltaSync guard for .invalid background task

/// `runInitialSync()` now guards `deltaTaskBox.value != .invalid` before calling
/// `runDeltaSync()`. Without this guard, iOS could kill the process mid-upload when
/// no valid background execution time was granted.
///
/// Direct unit-testing requires UIApplication, which is unavailable in the test
/// target. The tests below verify the surrounding contracts: that `runInitialSync()`
/// does not crash and leaves `SyncManager` in a consistent state after completion.
@MainActor
final class DeferredDeltaSyncGuardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SyncManager.shared.resetState()
    }

    override func tearDown() {
        SyncManager.shared.resetState()
        super.tearDown()
    }

    /// `runInitialSync()` must complete without crashing and leave `isInitialSyncRunning`
    /// as `false`. Validates the code path that contains the new `.invalid` guard.
    func test_runInitialSync_completesWithoutCrash_andClearsFlag() async {
        await SyncManager.shared.runInitialSync()
        XCTAssertFalse(
            SyncManager.shared.isInitialSyncRunning,
            "isInitialSyncRunning must be false after runInitialSync completes"
        )
    }

    /// Calling `runInitialSync()` twice concurrently must not cause a double-entry:
    /// `isInitialSyncRunning` guard blocks the second call.
    func test_runInitialSync_concurrentCall_isDroppedByGuard() async {
        async let first: Void = SyncManager.shared.runInitialSync()
        async let second: Void = SyncManager.shared.runInitialSync()
        _ = await (first, second)
        XCTAssertFalse(SyncManager.shared.isInitialSyncRunning)
    }

    /// After `runInitialSync()` completes, `isSyncing` must be `false` — the deferred
    /// delta sync (if any) cleans up properly regardless of the `.invalid` guard path.
    func test_runInitialSync_leavesIsSyncingFalse() async {
        await SyncManager.shared.runInitialSync()
        XCTAssertFalse(SyncManager.shared.isSyncing)
    }
}

// MARK: - Fix 2 (MEDIUM): submitDailySyncRequest returns Bool, flag set only on success

/// `submitDailySyncRequest()` now returns `Bool`. Both `scheduleDailySync()` and
/// `scheduleDailySyncIfNeeded()` set the `dailySyncScheduledKey` flag to the return
/// value, so a failed submit leaves the flag `false` — preventing permanent skip.
final class DailySyncFlagOnSuccessOnlyTests: XCTestCase {
    private let scheduledKey = "com.healthlogsync.dailySyncScheduled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: scheduledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: scheduledKey)
        super.tearDown()
    }

    /// `scheduleDailySync()` must leave the flag `false` when BGTaskScheduler rejects
    /// the submit (test target always rejects — no registered identifiers).
    func test_scheduleDailySync_setsFlag_onlyWhenSubmitSucceeds() {
        BackgroundTaskManager.shared.scheduleDailySync()
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: scheduledKey),
            "Flag must be false when BGTaskScheduler.submit fails"
        )
    }

    /// `scheduleDailySyncIfNeeded()` must leave the flag `false` when the submit fails.
    func test_scheduleDailySyncIfNeeded_whenFlagFalse_setsFlag_onlyOnSuccess() {
        UserDefaults.standard.set(false, forKey: scheduledKey)
        BackgroundTaskManager.shared.scheduleDailySyncIfNeeded()
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: scheduledKey),
            "Flag must be false when BGTaskScheduler.submit fails"
        )
    }

    /// When the flag is already `true` (guard fires), `scheduleDailySyncIfNeeded()`
    /// must not touch it — the guard-early-return path preserves the flag value.
    func test_scheduleDailySyncIfNeeded_whenFlagTrue_doesNotChangeFlag() {
        UserDefaults.standard.set(true, forKey: scheduledKey)
        BackgroundTaskManager.shared.scheduleDailySyncIfNeeded()
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: scheduledKey),
            "Flag must remain true when submit is skipped (guard-early-return)"
        )
    }
}

// MARK: - Fix 3 (MEDIUM): cancelPendingDailySync resets the flag

/// `cancelPendingDailySync()` now also resets `dailySyncScheduledKey` to `false`.
/// This prevents a stale `true` flag (written before a force-quit) from causing
/// `scheduleDailySyncIfNeeded()` to permanently skip submit after relaunch.
final class CancelPendingDailySyncFlagResetTests: XCTestCase {
    private let scheduledKey = "com.healthlogsync.dailySyncScheduled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: scheduledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: scheduledKey)
        super.tearDown()
    }

    /// `cancelPendingDailySync()` must reset the flag to `false`.
    func test_cancelPendingDailySync_resetsDailyScheduledFlag() {
        BackgroundTaskManager.shared.cancelPendingDailySync()
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: scheduledKey),
            "cancelPendingDailySync() must set dailySyncScheduledKey to false"
        )
    }

    /// Calling `cancelPendingDailySync()` when flag is already `false` must not crash
    /// and must leave the flag `false` (idempotent).
    func test_cancelPendingDailySync_whenFlagAlreadyFalse_isIdempotent() {
        UserDefaults.standard.set(false, forKey: scheduledKey)
        BackgroundTaskManager.shared.cancelPendingDailySync()
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: scheduledKey),
            "cancelPendingDailySync() must be idempotent when flag is already false"
        )
    }

    /// After `cancelPendingDailySync()`, `scheduleDailySyncIfNeeded()` attempts submit
    /// (flag is now false). The flag stays false because submit fails in the test target —
    /// but the key guarantee is that it does NOT permanently skip due to a stale `true`.
    func test_cancelThenScheduleIfNeeded_doesNotPermanentlySkip() {
        // Flag starts true (set in setUp).
        BackgroundTaskManager.shared.cancelPendingDailySync()
        // Flag is now false — scheduleDailySyncIfNeeded() will attempt submit.
        BackgroundTaskManager.shared.scheduleDailySyncIfNeeded()
        // Submit fails in test target, so flag stays false — not permanently blocked.
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: scheduledKey),
            "After cancel + scheduleDailySyncIfNeeded, flag must reflect submit outcome"
        )
    }
}

// MARK: - Fix 4 (LOW): NSLock prevents TOCTOU race in scheduleDailySync / scheduleDailySyncIfNeeded

/// `scheduleDailySync()` and `scheduleDailySyncIfNeeded()` are now protected by
/// `dailySyncLock` (NSLock) so concurrent invocations from different threads cannot
/// both observe flag=false simultaneously and issue duplicate BGTaskScheduler submits.
final class DailySyncLockThreadSafetyTests: XCTestCase {
    private let scheduledKey = "com.healthlogsync.dailySyncScheduled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: scheduledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: scheduledKey)
        super.tearDown()
    }

    /// Calling `scheduleDailySync()` and `scheduleDailySyncIfNeeded()` concurrently
    /// from multiple threads must not crash (no deadlock, no data race).
    func test_scheduleDailySync_isThreadSafe_multipleCallsDoNotCrash() {
        let iterations = 50
        let group = DispatchGroup()

        for _ in 0 ..< iterations {
            group.enter()
            DispatchQueue.global().async {
                BackgroundTaskManager.shared.scheduleDailySync()
                group.leave()
            }

            group.enter()
            DispatchQueue.global().async {
                BackgroundTaskManager.shared.scheduleDailySyncIfNeeded()
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Concurrent calls must complete without timeout or deadlock")
    }

    /// Interleaved `scheduleDailySync()` + `cancelPendingDailySync()` from multiple
    /// threads must not crash (cancelPendingDailySync() acquires dailySyncLock for its flag reset — no deadlock risk:
    /// scheduleDailySync also holds dailySyncLock but neither function calls the other
    /// while holding the lock, so contention is possible but deadlock is not).
    func test_scheduleDailySync_andCancel_concurrentlyDoNotCrash() {
        let group = DispatchGroup()

        for _ in 0 ..< 30 {
            group.enter()
            DispatchQueue.global().async {
                BackgroundTaskManager.shared.scheduleDailySync()
                group.leave()
            }

            group.enter()
            DispatchQueue.global().async {
                BackgroundTaskManager.shared.cancelPendingDailySync()
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Concurrent schedule + cancel must not deadlock")
    }
}

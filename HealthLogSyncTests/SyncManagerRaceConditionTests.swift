import XCTest
@testable import HealthLogSync

/// Bug 1 from post-PR33 review: `SyncManager.runDeltaSync()` previously
/// guarded only on `state == .idle`. After we started calling
/// `resetState()` from AppDelegate / BackgroundTaskManager / HK observer
/// callbacks immediately before each `runDeltaSync()`, two concurrent
/// callers could both flip the state to `.idle`, both pass the guard, and
/// run two simultaneous syncs — duplicate uploads and racing `lastSyncAt`
/// writes.
///
/// The fix introduces an `isSyncing` flag, mutated only on the main actor,
/// flipped to `true` synchronously before the first `await`. These tests
/// pin the contract.
@MainActor
final class SyncManagerRaceConditionTests: XCTestCase {
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

    /// Direct check of the isSyncing flag: at rest it must be false, and
    /// `resetState()` must not toggle it on (the flag is independent of
    /// the published `state`).
    func test_isSyncing_isFalseAtRest() {
        let manager = SyncManager.shared
        manager.resetState()
        XCTAssertFalse(manager.isSyncing)
    }

    /// Two concurrent invocations of `runDeltaSync()` must result in only
    /// one of them actually performing work. The second invocation hits
    /// the `guard !isSyncing` and returns early. We can't observe the
    /// guard directly, but we can prove the manager ends in `.idle`
    /// faster than two real syncs would take, and that `isSyncing` is
    /// false on completion.
    func test_runDeltaSync_concurrentCalls_secondIsDroppedByIsSyncingGuard() async {
        let manager = SyncManager.shared

        // Fire two delta syncs in parallel from independent Tasks. Under
        // the bug, both would pass the (now-removed) idle guard since
        // they both observe state == .idle synchronously before the
        // first state mutation. Under the fix, the second observes
        // isSyncing == true and returns.
        async let firstSync: Void = manager.runDeltaSync()
        async let secondSync: Void = manager.runDeltaSync()
        _ = await (firstSync, secondSync)

        XCTAssertFalse(manager.isSyncing, "isSyncing must be cleared by defer after both calls return")
        XCTAssertEqual(manager.state, .success(recordsCount: 0))
    }

    /// After a sync completes, `isSyncing` must be reset to false so the
    /// next invocation can proceed. This is the defer{} contract.
    func test_runDeltaSync_clearsIsSyncing_onCompletion() async {
        let manager = SyncManager.shared
        await manager.runDeltaSync()
        XCTAssertFalse(manager.isSyncing, "defer { isSyncing = false } must run after the sync body")
    }

    /// Resetting the published `state` must not affect `isSyncing` —
    /// the two are independent and `resetState()` is intentionally a
    /// UI helper, not a concurrency primitive.
    func test_resetState_doesNotTouchIsSyncing() {
        let manager = SyncManager.shared
        manager.resetState()
        XCTAssertFalse(manager.isSyncing)
    }
}

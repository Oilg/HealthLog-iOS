import XCTest
@testable import HealthLogSync

@MainActor
final class SyncManagerTests: XCTestCase {
    // MARK: - SyncState equality

    func test_syncState_idle_equalsIdle() {
        XCTAssertEqual(SyncState.idle, SyncState.idle)
    }

    func test_syncState_syncing_equalsSameProgress() {
        XCTAssertEqual(SyncState.syncing(progress: "Загрузка…"), SyncState.syncing(progress: "Загрузка…"))
    }

    func test_syncState_syncing_notEqualsDifferentProgress() {
        XCTAssertNotEqual(SyncState.syncing(progress: "A"), SyncState.syncing(progress: "B"))
    }

    func test_syncState_success_equalsSameCount() {
        XCTAssertEqual(SyncState.success(recordsCount: 42), SyncState.success(recordsCount: 42))
    }

    func test_syncState_success_notEqualsDifferentCount() {
        XCTAssertNotEqual(SyncState.success(recordsCount: 0), SyncState.success(recordsCount: 1))
    }

    func test_syncState_failure_alwaysEqualFailure() {
        // Two different errors still match — we only care that a failure occurred
        let e1 = NSError(domain: "a", code: 1)
        let e2 = NSError(domain: "b", code: 2)
        XCTAssertEqual(SyncState.failure(e1), SyncState.failure(e2))
    }

    func test_syncState_differentCases_areNotEqual() {
        XCTAssertNotEqual(SyncState.idle, SyncState.success(recordsCount: 0))
        XCTAssertNotEqual(SyncState.syncing(progress: ""), SyncState.idle)
        XCTAssertNotEqual(SyncState.success(recordsCount: 0), SyncState.failure(NSError(domain: "", code: 0)))
    }

    // MARK: - resetState

    func test_resetState_setsStateToIdle() {
        let manager = SyncManager.shared
        manager.resetState()
        XCTAssertEqual(manager.state, .idle)
    }

    func test_resetState_isIdempotent() {
        let manager = SyncManager.shared
        manager.resetState()
        manager.resetState()
        XCTAssertEqual(manager.state, .idle)
    }

    // MARK: - Silent-push fallback decision (BackgroundTaskManager)

    func test_decideSilentPushAction_runsSyncWhenDeviceUnlocked() {
        // Unlocked phone: HealthKit reads succeed, run sync inline on the silent push.
        XCTAssertEqual(
            BackgroundTaskManager.decideSilentPushAction(isProtectedDataAvailable: true),
            .runSync
        )
    }

    func test_decideSilentPushAction_schedulesImmediateWhenDeviceLocked() {
        // Locked phone: HealthKit returns errorHealthDataUnavailable, so the silent
        // push must defer to a BGProcessingTask instead of uploading an empty batch.
        XCTAssertEqual(
            BackgroundTaskManager.decideSilentPushAction(isProtectedDataAvailable: false),
            .scheduleImmediate
        )
    }

    func test_scheduleImmediateSync_doesNotCrash() {
        // Smoke test: submission may fail under test host (no entitlement / simulator)
        // and that is fine — BGTaskScheduler errors are logged, never thrown.
        // We only assert the method is safe to invoke from any call site.
        BackgroundTaskManager.shared.scheduleImmediateSync()
        BackgroundTaskManager.shared.cancelPendingImmediateSync()
    }
}

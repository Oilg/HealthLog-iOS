@testable import HealthLogSync
import XCTest

/// Tests covering the two fixes in `fix/sync-idle-state-and-empty-window`:
///
/// 1. Repeated background-triggered delta syncs must not be silently dropped.
///    Previously `runDeltaSync()` had `guard case .idle = state else { return }`
///    and `resetState()` was only invoked from the UI button on DashboardView.
///    After a first sync left `state == .success`, every subsequent silent
///    push / BGProcessingTask exited the function immediately. The fix calls
///    `SyncManager.shared.resetState()` from AppDelegate and
///    BackgroundTaskManager before kicking off `runDeltaSync()`.
///
/// 2. `lastSyncAt` must NOT be advanced when HealthKit returns zero records.
///    Otherwise the next sync window starts at "now" and any records the watch
///    delivers a few seconds later are lost forever. `lastSyncAt` is owned
///    exclusively by `SyncService.uploadRecords()` after a successful upload.
///
/// Note on test scope: `SyncManager` consumes its dependencies via singletons
/// (`HealthKitManager.shared`, `SyncService.shared`), so we cannot inject mocks.
/// In the unit-test target HealthKit is unauthorized, which makes
/// `fetchRecords(from:to:)` return an empty array — exactly the branch the
/// second fix protects. That lets us drive `runDeltaSync()` end-to-end through
/// the empty-records path without any network or HealthKit access.
@MainActor
final class SyncManagerDeltaSyncTests: XCTestCase {
    private var savedLastSyncAt: Date?

    override func setUp() {
        super.setUp()
        // Snapshot UserDefaults so the test doesn't leak state into the
        // simulator's shared defaults between runs.
        savedLastSyncAt = UserDefaultsManager.shared.lastSyncAt
        SyncManager.shared.resetState()
    }

    override func tearDown() {
        UserDefaultsManager.shared.lastSyncAt = savedLastSyncAt
        SyncManager.shared.resetState()
        super.tearDown()
    }

    // MARK: - Bug 1: idle-state guard must not lock out background callers

    /// Reproduces the original bug and proves the fix's contract:
    /// after a first `runDeltaSync()` leaves the manager in `.success`, a
    /// second call to `runDeltaSync()` would be skipped by
    /// `guard case .idle = state`. The fix in AppDelegate and
    /// BackgroundTaskManager is to call `resetState()` before each sync; after
    /// that the second sync must execute again and again leave state at
    /// `.success(recordsCount: 0)` (HealthKit is unauthorized in the test
    /// target, so the empty-records branch runs).
    func test_runDeltaSync_afterFirstSyncCompletes_secondCallIsNotSkipped_whenResetStateIsInvoked() async {
        let manager = SyncManager.shared

        // First sync — drives state to .success(0) via the empty-records path.
        await manager.runDeltaSync()
        XCTAssertEqual(manager.state, .success(recordsCount: 0))

        // Without resetState(), runDeltaSync would now early-return and state
        // would remain identical to whatever the first run produced. We invoke
        // the exact call pattern the fix introduces in AppDelegate /
        // BackgroundTaskManager: resetState() right before runDeltaSync().
        manager.resetState()
        XCTAssertEqual(manager.state, .idle, "Precondition for second runDeltaSync")

        // Second sync — must run again rather than being silently skipped.
        await manager.runDeltaSync()
        XCTAssertEqual(
            manager.state,
            .success(recordsCount: 0),
            "Second runDeltaSync after resetState must execute and reach a terminal state again"
        )
    }

    /// Direct, isolated proof that the guard expression in runDeltaSync flips
    /// back to passing only after resetState() runs. This is the contract
    /// AppDelegate and BackgroundTaskManager now depend on.
    func test_resetState_returnsToIdle_fromAnyPostSyncState() async {
        let manager = SyncManager.shared

        await manager.runDeltaSync() // -> .success(0) via empty-records branch
        XCTAssertNotEqual(manager.state, .idle, "Sync should leave the manager in a terminal, non-idle state")

        manager.resetState()
        XCTAssertEqual(manager.state, .idle)
    }

    // MARK: - Bug 2: lastSyncAt must not advance when no records are fetched

    /// When HealthKit returns 0 records, `runDeltaSync()` previously advanced
    /// `lastSyncAt` to "now", causing the next sync window to start at the
    /// future and silently drop any data the watch delivered a few seconds
    /// later. The fix removes that write; `lastSyncAt` is owned exclusively by
    /// `SyncService.uploadRecords()` and must stay at its previous value.
    func test_runDeltaSync_doesNotAdvanceLastSyncAt_whenHealthKitReturnsNoRecords() async {
        // Anchor lastSyncAt at a deterministic point in the past.
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        UserDefaultsManager.shared.lastSyncAt = anchor

        await SyncManager.shared.runDeltaSync()

        XCTAssertEqual(
            UserDefaultsManager.shared.lastSyncAt,
            anchor,
            "lastSyncAt must remain at its previous value when 0 records are fetched; " +
                "advancing it would discard records that the watch hadn't delivered yet"
        )
        XCTAssertEqual(
            SyncManager.shared.state,
            .success(recordsCount: 0),
            "Empty-records path should still report success with 0 records"
        )
    }

    /// Same contract from a cold start: lastSyncAt was nil and must stay nil
    /// after an empty-records run, so the next sync still falls back to the
    /// 7-day delta window instead of starting at `now`.
    func test_runDeltaSync_keepsLastSyncAtNil_whenStartingColdWithNoRecords() async {
        UserDefaultsManager.shared.lastSyncAt = nil

        await SyncManager.shared.runDeltaSync()

        XCTAssertNil(
            UserDefaultsManager.shared.lastSyncAt,
            "Cold-start empty-records run must not seed lastSyncAt; " +
                "ownership belongs to SyncService.uploadRecords"
        )
    }

    /// Across multiple back-to-back empty syncs, `lastSyncAt` must remain
    /// pinned to its original anchor — proving the cursor never drifts under
    /// repeated background invocations on a device whose watch is slow to
    /// hand off data.
    func test_runDeltaSync_lastSyncAtStaysPinned_acrossRepeatedEmptySyncs() async {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        UserDefaultsManager.shared.lastSyncAt = anchor

        for _ in 0 ..< 3 {
            SyncManager.shared.resetState()
            await SyncManager.shared.runDeltaSync()
            XCTAssertEqual(
                UserDefaultsManager.shared.lastSyncAt,
                anchor,
                "lastSyncAt drifted across repeated empty syncs"
            )
        }
    }
}

import Foundation
import UIKit

enum SyncState: Equatable {
    case idle
    case syncing(progress: String)
    case success(recordsCount: Int)
    case failure(Error)

    static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case let (.syncing(lhs), .syncing(rhs)): return lhs == rhs
        case let (.success(lhs), .success(rhs)): return lhs == rhs
        case (.failure, .failure): return true
        default: return false
        }
    }
}

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published private(set) var state: SyncState = .idle
    @Published private(set) var isInitialSyncRunning = false
    @Published private(set) var initialSyncProgress: String = ""

    private let batchDuration: TimeInterval = 30 * 24 * 60 * 60
    private let deltaSyncWindow: TimeInterval = 7 * 24 * 60 * 60
    private let uploadChunkSize = 9000

    /// Concurrency guard for `runDeltaSync()`.
    ///
    /// The previous `guard case .idle = state else { return }` was bypassed
    /// after we started calling `resetState()` before each background sync
    /// (HK observer, silent push, BGProcessingTask). Two parallel callers
    /// could each reset the state to `.idle` and pass the guard simultaneously,
    /// kicking off two concurrent uploads. The flag below is mutated only on
    /// the main actor, so reading and flipping it is atomic by construction.
    private(set) var isSyncing = false

    /// Set to `true` when `runDeltaSync()` is called while `isInitialSyncRunning`
    /// is `true` — i.e. a HKObserver event arrived during initial sync. After
    /// `runInitialSync` finishes it checks this flag and runs one delta sync so
    /// no observer events are permanently lost.
    private var pendingDeltaSyncAfterInitial = false

    private init() {}

    /// Runs a delta sync.
    /// - Returns: `true` if a sync was actually performed (guard passed and sync ran),
    ///   `false` if the call was dropped because another sync is already in progress.
    ///   The return value is marked `@discardableResult` so existing call sites that
    ///   do not need the value compile without change.
    @discardableResult
    func runDeltaSync() async -> Bool {
        // Atomic on @MainActor: both read and write happen on the same
        // executor, so two concurrent callers cannot both pass this guard.
        // Also block when an initial sync is in progress — both operations
        // fetch from overlapping HealthKit windows and would produce
        // duplicate uploads. When blocked by initial sync, set a pending flag
        // so runInitialSync() triggers one delta sync when it completes,
        // ensuring HKObserver events received during initial sync are not lost.
        guard !isSyncing, !isInitialSyncRunning else {
            if isInitialSyncRunning { pendingDeltaSyncAfterInitial = true }
            return false
        }
        isSyncing = true
        defer { isSyncing = false }

        state = .syncing(progress: "Синхронизация...")

        do {
            let to = Date()
            let from = UserDefaultsManager.shared.lastSyncAt ?? Date().addingTimeInterval(-deltaSyncWindow)
            let records = await HealthKitManager.shared.fetchRecords(from: from, to: to)

            if records.isEmpty {
                // Do NOT update lastSyncAt here: HealthKit may simply not have synced
                // from the watch yet. lastSyncAt is updated only after a successful
                // upload in SyncService.uploadRecords(), preserving the from-window
                // until real data is delivered.
                state = .success(recordsCount: 0)
                return true
            }

            var totalSynced = 0
            for chunkStart in stride(from: 0, to: records.count, by: uploadChunkSize) {
                let chunk = Array(records[chunkStart ..< min(chunkStart + uploadChunkSize, records.count)])
                let response = try await SyncService.shared.uploadRecords(from: from, to: to, records: chunk)
                totalSynced += response.syncedRecords
            }
            state = .success(recordsCount: totalSynced)
        } catch {
            state = .failure(error)
        }
        return true
    }

    func runInitialSync() async {
        // Also block when a delta sync is running — same overlapping-window risk.
        guard !isInitialSyncRunning, !isSyncing else { return }
        isInitialSyncRunning = true

        // Use BackgroundTaskBox (a reference-type wrapper with NSLock) so the
        // expiration handler (background thread) and this @MainActor body share
        // the identifier safely — same pattern as `runSilentPushSync` in AppDelegate.
        let taskBox = BackgroundTaskBox()
        taskBox.value = UIApplication.shared.beginBackgroundTask(withName: "InitialSync") {
            taskBox.endIfNeeded()
        }

        do {
            let calendar = Calendar.current
            let to = Date()

            let earliestDate = await HealthKitManager.shared.earliestDataDate()
            let startPoint = UserDefaultsManager.shared.initialSyncProgress
                ?? earliestDate
                ?? to.addingTimeInterval(-deltaSyncWindow)

            var batchStart = startPoint

            while batchStart < to {
                let batchEnd = min(batchStart.addingTimeInterval(batchDuration), to)

                let monthFormatter = DateFormatter()
                monthFormatter.dateFormat = "LLLL yyyy"
                monthFormatter.locale = Locale(identifier: "ru_RU")
                initialSyncProgress = monthFormatter.string(from: batchStart)

                let records = await HealthKitManager.shared.fetchRecords(from: batchStart, to: batchEnd)

                if !records.isEmpty {
                    for chunkStart in stride(from: 0, to: records.count, by: uploadChunkSize) {
                        let chunk = Array(records[chunkStart ..< min(chunkStart + uploadChunkSize, records.count)])
                        _ = try await SyncService.shared.uploadRecords(from: batchStart, to: batchEnd, records: chunk)
                    }
                }

                UserDefaultsManager.shared.initialSyncProgress = batchEnd
                batchStart = batchEnd

                _ = calendar
            }

            UserDefaultsManager.shared.initialSyncCompleted = true
            UserDefaultsManager.shared.initialSyncProgress = nil
        } catch {
            state = .failure(error)
        }

        taskBox.endIfNeeded()
        isInitialSyncRunning = false

        // If a HKObserver event arrived during initial sync, run one delta sync
        // now so those samples are not permanently lost.
        if pendingDeltaSyncAfterInitial {
            pendingDeltaSyncAfterInitial = false
            await runDeltaSync()
        }
    }

    func resetState() {
        // Do not overwrite an active `.syncing` state — a concurrent caller
        // resetting state while a sync is in flight would clear the progress
        // indicator and unblock the `isSyncing` guard prematurely (it doesn't,
        // because `isSyncing` is independent, but the published `state` would
        // become stale/misleading). Also guard on `isInitialSyncRunning` because
        // initial sync holds `isSyncing = false` while it runs, so without this
        // check `resetState()` would overwrite the in-progress state.
        guard !isSyncing, !isInitialSyncRunning else { return }
        state = .idle
    }

    /// Clears a stale `.failure` state without checking the sync-running flags.
    /// Use in `applicationWillEnterForeground` to remove a lingering error banner
    /// even when a sync is in progress (the banner should not survive a foreground
    /// transition regardless of whether the app is currently syncing).
    func clearFailureState() {
        guard case .failure = state else { return }
        state = .idle
    }
}

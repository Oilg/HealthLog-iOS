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

    private init() {}

    func runDeltaSync() async {
        // Atomic on @MainActor: both read and write happen on the same
        // executor, so two concurrent callers cannot both pass this guard.
        // Also block when an initial sync is in progress — both operations
        // fetch from overlapping HealthKit windows and would produce
        // duplicate uploads.
        guard !isSyncing, !isInitialSyncRunning else { return }
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
                return
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
    }

    func runInitialSync() async {
        // Also block when a delta sync is running — same overlapping-window risk.
        guard !isInitialSyncRunning, !isSyncing else { return }
        isInitialSyncRunning = true

        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "InitialSync") {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
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

        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
        }
        isInitialSyncRunning = false
    }

    func resetState() {
        // Do not overwrite an active `.syncing` state — a concurrent caller
        // resetting state while a sync is in flight would clear the progress
        // indicator and unblock the `isSyncing` guard prematurely (it doesn't,
        // because `isSyncing` is independent, but the published `state` would
        // become stale/misleading). If a sync is already running, this call
        // is a no-op.
        guard !isSyncing else { return }
        state = .idle
    }
}

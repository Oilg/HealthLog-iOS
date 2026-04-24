import Foundation

enum SyncState: Equatable {
    case idle
    case syncing(progress: String)
    case success(recordsCount: Int)
    case failure(Error)

    static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.syncing(let l), .syncing(let r)): return l == r
        case (.success(let l), .success(let r)): return l == r
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

    private init() {}

    func runDeltaSync() async {
        guard case .idle = state else { return }
        state = .syncing(progress: "Синхронизация...")

        do {
            let to = Date()
            let from = UserDefaultsManager.shared.lastSyncAt ?? Date().addingTimeInterval(-deltaSyncWindow)
            let records = await HealthKitManager.shared.fetchRecords(from: from, to: to)

            if records.isEmpty {
                state = .success(recordsCount: 0)
                return
            }

            let response = try await SyncService.shared.uploadRecords(from: from, to: to, records: records)
            state = .success(recordsCount: response.syncedRecords)
        } catch {
            state = .failure(error)
        }
    }

    func runInitialSync() async {
        guard !isInitialSyncRunning else { return }
        isInitialSyncRunning = true

        do {
            let calendar = Calendar.current
            let to = Date()

            let startPoint = UserDefaultsManager.shared.initialSyncProgress
                ?? (await HealthKitManager.shared.earliestDataDate())
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
                    _ = try await SyncService.shared.uploadRecords(from: batchStart, to: batchEnd, records: records)
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

        isInitialSyncRunning = false
    }

    func resetState() {
        state = .idle
    }
}

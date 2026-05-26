import BackgroundTasks
import Foundation
import os

/// Decision returned by `decideSilentPushAction` — pulled out as a small enum
/// so the silent-push fallback logic stays unit-testable without UIApplication.
enum SilentPushAction: Equatable {
    /// Device is unlocked, HealthKit reads will work — run the sync inline.
    case runSync
    /// Device is locked (`isProtectedDataAvailable == false`). HealthKit reads
    /// return `errorHealthDataUnavailable`, so defer to BGProcessingTask which
    /// will fire when the user next unlocks the device.
    case scheduleImmediate
}

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private let dailySyncTaskIdentifier = "com.healthlogsync.dailysync"
    private let immediateSyncTaskIdentifier = "com.healthlogsync.immediatesync"
    private let log = Logger(subsystem: "com.healthlogsync", category: "BackgroundTask")

    private init() {}

    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: dailySyncTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleSyncTask(processingTask, rescheduleDaily: true)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: immediateSyncTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            // Immediate sync is one-shot but we MUST still reschedule the daily sync.
            // When iOS launches a killed app via BGProcessingTask, no other code path
            // calls scheduleDailySync() — without this the daily sync would be lost
            // until the user next foregrounds the app manually.
            self.handleSyncTask(processingTask, rescheduleDaily: true)
        }
    }

    /// Schedules the regular daily sync at the next 10:00 local time.
    func scheduleDailySync() {
        cancelPendingDailySync()

        let request = BGProcessingTaskRequest(identifier: dailySyncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        var components = DateComponents()
        components.hour = 10
        components.minute = 0
        if let nextRun = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) {
            request.earliestBeginDate = nextRun
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("scheduleDailySync submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Schedules a one-shot BGProcessingTask to run as soon as iOS allows.
    /// Use when a silent push arrived while the device was locked: HealthKit reads
    /// are blocked by file protection, but iOS will fire this BGTask shortly after
    /// the user unlocks the device, at which point HealthKit data becomes readable.
    func scheduleImmediateSync() {
        cancelPendingImmediateSync()

        let request = BGProcessingTaskRequest(identifier: immediateSyncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Intentionally no earliestBeginDate — we want this ASAP.
        request.earliestBeginDate = nil

        do {
            try BGTaskScheduler.shared.submit(request)
            log.info("scheduleImmediateSync submitted")
        } catch {
            log.error("scheduleImmediateSync submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelPendingDailySync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: dailySyncTaskIdentifier)
    }

    func cancelPendingImmediateSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: immediateSyncTaskIdentifier)
    }

    /// Pure decision function — chosen action given device lock state.
    /// Extracted so silent-push fallback can be exercised without UIApplication.
    static func decideSilentPushAction(isProtectedDataAvailable: Bool) -> SilentPushAction {
        isProtectedDataAvailable ? .runSync : .scheduleImmediate
    }

    private func handleSyncTask(_ task: BGProcessingTask, rescheduleDaily: Bool) {
        if rescheduleDaily {
            scheduleDailySync()
        }

        // `setTaskCompleted` must be invoked exactly once. The expiration handler
        // and the natural sync completion both want to call it — without a guard
        // an expiration that fires just before the sync finishes results in a
        // double call, which is documented undefined behaviour and trips
        // assertion failures inside BackgroundTasks.framework. NSLock keeps the
        // check-and-flip atomic across the BGTaskScheduler thread (expiration
        // handler) and the MainActor (sync completion).
        let completionLock = NSLock()
        var completed = false
        let completeOnce: (Bool) -> Void = { success in
            completionLock.lock()
            let alreadyCompleted = completed
            completed = true
            completionLock.unlock()
            guard !alreadyCompleted else { return }
            task.setTaskCompleted(success: success)
        }

        let syncTask = Task { @MainActor in
            // Reset state so a previous .success/.failure from a prior run does not
            // make runDeltaSync exit immediately via its `guard case .idle = state`.
            SyncManager.shared.resetState()
            await SyncManager.shared.runDeltaSync()
            completeOnce(true)
        }

        task.expirationHandler = {
            syncTask.cancel()
            completeOnce(false)
        }
    }
}

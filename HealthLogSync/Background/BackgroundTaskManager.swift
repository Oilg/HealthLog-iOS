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

    /// UserDefaults key tracking whether a daily sync BGProcessingTask is already
    /// pending. Set to `true` after each `submit`, cleared at the start of the
    /// daily task handler so the next foreground/immediate-sync can re-schedule.
    ///
    /// BGTaskScheduler.submit(_:) **replaces** any existing pending request with
    /// the same identifier (contrary to older docs that described it as a no-op).
    /// Tracking the flag ourselves is the only reliable way to avoid clobbering a
    /// valid same-day pending request when an immediate sync fires after 10:00.
    private let dailySyncScheduledKey = "com.healthlogsync.dailySyncScheduled"

    private init() {}

    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: dailySyncTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            // Flag reset is handled atomically inside scheduleDailySync() which is
            // called by handleSyncTask(rescheduleDailyReplacingExisting: true).
            self.handleSyncTask(processingTask, rescheduleDailyReplacingExisting: true)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: immediateSyncTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            // Immediate sync is one-shot but we MUST still ensure the daily sync
            // is scheduled. When iOS launches a killed app via BGProcessingTask,
            // no other code path calls scheduleDailySync(). We use
            // scheduleDailySyncIfNeeded() (flag-guarded) so that an existing
            // daily sync pending for today is NOT discarded — submitting again
            // would replace it and push the next run to tomorrow, skipping one day.
            self.handleSyncTask(processingTask, rescheduleDailyReplacingExisting: false)
        }
    }

    /// Schedules the regular daily sync at the next 10:00 local time.
    /// Cancels any pending daily sync first so duplicate requests are avoided.
    func scheduleDailySync() {
        cancelPendingDailySync()
        // Reset flag before submit so the window between reset and set is contained
        // within this single function call, eliminating the TOCTOU gap that existed
        // when the reset was done separately in the daily task handler.
        UserDefaults.standard.set(false, forKey: dailySyncScheduledKey)
        submitDailySyncRequest()
        UserDefaults.standard.set(true, forKey: dailySyncScheduledKey)
    }

    /// Schedules the regular daily sync only when no pending request is already
    /// tracked. Used from the immediate-sync handler: BGTaskScheduler.submit(_:)
    /// *replaces* an existing pending request with the same identifier, so calling
    /// it unconditionally after 10:00 would push today's already-queued daily sync
    /// to tomorrow, silently skipping one day.
    func scheduleDailySyncIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: dailySyncScheduledKey) else {
            log.info("Daily sync already scheduled — skipping submit")
            return
        }
        submitDailySyncRequest()
        UserDefaults.standard.set(true, forKey: dailySyncScheduledKey)
    }

    private func submitDailySyncRequest() {
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

    /// - Parameters:
    ///   - task: The BGProcessingTask to handle.
    ///   - rescheduleDailyReplacingExisting: When `true` (daily handler), cancel any
    ///     pending daily sync and submit a fresh one. When `false` (immediate handler),
    ///     only submit if not already pending — avoids skipping a day by cancelling a
    ///     valid pending daily sync.
    private func handleSyncTask(_ task: BGProcessingTask, rescheduleDailyReplacingExisting: Bool) {
        if rescheduleDailyReplacingExisting {
            scheduleDailySync()
        } else {
            scheduleDailySyncIfNeeded()
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
            // runDeltaSync returns false either when another sync is already running
            // (concurrency guard fired) or when the sync threw an error (fix 1).
            // When another sync is already running, the work is being done — treat
            // as success so iOS does not retry unnecessarily. Real errors are also
            // reported as success here because iOS retry on failure can cause a
            // cascade when daily+immediate tasks fire simultaneously; errors are
            // surfaced via SyncManager.state = .failure for the UI.
            _ = await SyncManager.shared.runDeltaSync()
            completeOnce(true)
        }

        task.expirationHandler = {
            syncTask.cancel()
            completeOnce(false)
        }
    }
}

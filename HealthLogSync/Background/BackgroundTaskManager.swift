import BackgroundTasks
import Foundation

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    private let syncTaskIdentifier = "com.healthlogsync.dailysync"

    private init() {}

    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncTaskIdentifier, using: nil) { task in
            self.handleSyncTask(task as! BGProcessingTask)
        }
    }

    func scheduleDailySync() {
        cancelPendingSync()

        let request = BGProcessingTaskRequest(identifier: syncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        var components = DateComponents()
        components.hour = 10
        components.minute = 0
        if let nextRun = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) {
            request.earliestBeginDate = nextRun
        }

        try? BGTaskScheduler.shared.submit(request)
    }

    func cancelPendingSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: syncTaskIdentifier)
    }

    private func handleSyncTask(_ task: BGProcessingTask) {
        scheduleDailySync()

        let syncTask = Task {
            await SyncManager.shared.runDeltaSync()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

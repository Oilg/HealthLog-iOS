import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        BackgroundTaskManager.shared.registerTasks()
        BackgroundTaskManager.shared.scheduleDailySync()
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        startHealthKitBackgroundObservation()
        return true
    }

    /// Wires HealthKit background delivery + observer so the watch pushing new
    /// samples to the iPhone wakes us up and triggers a sync. Independent of
    /// silent pushes — this is the primary, OS-managed path.
    private func startHealthKitBackgroundObservation() {
        HealthKitManager.shared.enableBackgroundDeliveryAndStartObservers {
            // HKObserverQuery callback runs on a background queue.
            // SyncManager is @MainActor — hop over before touching it.
            Task { @MainActor in
                SyncManager.shared.resetState()
                await SyncManager.shared.runDeltaSync()
            }
        }
    }

    func applicationWillEnterForeground(_: UIApplication) {
        BackgroundTaskManager.shared.scheduleDailySync()

        // Foreground is the most reliable trigger we have. iOS background policy
        // (battery, killed state, BGProcessingTask budget) frequently suppresses
        // silent pushes and BGAppRefresh, so a user-initiated foreground brings
        // us the only deterministic opportunity to push fresh HealthKit data to
        // the server. resetState() unblocks the .idle guard in runDeltaSync()
        // when the previous run left us in .success/.failure — exactly the same
        // pattern the analysis-ready push path already uses below.
        Task { @MainActor in
            SyncManager.shared.resetState()
            await SyncManager.shared.runDeltaSync()
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func applicationDidEnterBackground(_: UIApplication) {
        BackgroundTaskManager.shared.scheduleDailySync()
    }

    // MARK: - APNs registration

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await AuthService.shared.registerDeviceToken(token)
        }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {
        // APNs registration failed (simulator or missing entitlement) — silent push fallback to BGProcessingTask
    }

    // MARK: - Remote notifications (silent + analysis-ready)

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let aps = userInfo["aps"] as? [String: Any]
        let contentAvailable = aps?["content-available"] as? Int
        let type = userInfo["type"] as? String

        if type == "analysis_ready" {
            NotificationCenter.default.post(name: .analysisReady, object: nil)
            completionHandler(.newData)
            return
        }

        guard contentAvailable == 1 else {
            completionHandler(.noData)
            return
        }

        // When the device is locked, HealthKit reads return errorHealthDataUnavailable
        // and fetchRecords yields an empty array — the sync would then upload nothing
        // and miss this opportunity. Defer to a BGProcessingTask that fires once the
        // user unlocks the device, when HealthKit data becomes readable again.
        let action = BackgroundTaskManager.decideSilentPushAction(
            isProtectedDataAvailable: UIApplication.shared.isProtectedDataAvailable
        )
        switch action {
        case .scheduleImmediate:
            BackgroundTaskManager.shared.scheduleImmediateSync()
            completionHandler(.noData)
        case .runSync:
            Task { @MainActor in
                // Reset state so a previous .success/.failure does not block this run
                // (runDeltaSync guards on .idle and resetState is only called from UI otherwise).
                SyncManager.shared.resetState()
                await SyncManager.shared.runDeltaSync()
                completionHandler(.newData)
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show notifications even when the app is in the foreground.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let type = notification.request.content.userInfo["type"] as? String
        if type == "analysis_ready" {
            NotificationCenter.default.post(name: .analysisReady, object: nil)
        }
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle tap on a delivered notification.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let type = response.notification.request.content.userInfo["type"] as? String
        if type == "analysis_ready" {
            NotificationCenter.default.post(name: .analysisReady, object: nil)
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let analysisReady = Notification.Name("com.healthlogsync.analysisReady")
}

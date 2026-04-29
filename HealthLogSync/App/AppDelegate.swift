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
        return true
    }

    func applicationWillEnterForeground(_: UIApplication) {
        BackgroundTaskManager.shared.scheduleDailySync()
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

        Task { @MainActor in
            await SyncManager.shared.runDeltaSync()
            completionHandler(.newData)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Show notifications even when the app is in the foreground
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

    // Handle tap on a delivered notification
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

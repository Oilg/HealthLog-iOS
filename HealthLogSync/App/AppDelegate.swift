import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        BackgroundTaskManager.shared.registerTasks()
        BackgroundTaskManager.shared.scheduleDailySync()
        requestNotificationPermission()
        return true
    }

    func applicationWillEnterForeground(_: UIApplication) {
        // Reschedule in case the app missed the last scheduled window while terminated.
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

    // MARK: - Silent push → trigger sync

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let aps = userInfo["aps"] as? [String: Any],
              let contentAvailable = aps["content-available"] as? Int,
              contentAvailable == 1
        else {
            completionHandler(.noData)
            return
        }

        Task { @MainActor in
            await SyncManager.shared.runDeltaSync()
            completionHandler(.newData)
        }
    }
}

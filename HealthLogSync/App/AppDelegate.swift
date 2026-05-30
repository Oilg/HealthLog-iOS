import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Stores a push action that arrived before MainTabView subscribed to NotificationCenter.
    /// MainTabView reads and clears this in `.onAppear` / `.task` to handle cold-start navigations.
    @MainActor static var pendingAction: String?

    /// Set by `navigateToProfile()` when the DOB highlight banner must be shown after SettingsView
    /// has fully appeared. SettingsView reads and clears this inside `.task` to avoid a race where
    /// `.onReceive` fires before the view is subscribed.
    @MainActor static var pendingHighlightDOB: Bool = false

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
        BackgroundTaskManager.shared.scheduleDailySyncIfNeeded()
    }

    func applicationDidBecomeActive(_: UIApplication) {
        UNUserNotificationCenter.current().setBadgeCount(0)
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
            runSilentPushSync(completionHandler: completionHandler)
        }
    }

    /// Runs the silent-push delta sync without holding iOS to its 30-second
    /// deadline for `completionHandler`. The 30-second budget is for the
    /// completion call itself — exceeding it kills the app and locks us out
    /// of silent pushes for a while, which is why we never await the full
    /// sync before invoking `completionHandler`.
    ///
    /// Flow:
    ///   1. Begin a `UIBackgroundTaskIdentifier` so iOS keeps us alive past
    ///      `completionHandler` for the actual upload work.
    ///   2. Call `completionHandler(.newData)` immediately so iOS marks the
    ///      push as handled in time.
    ///   3. Run the sync in the background and end the task when done
    ///      (also from the expiration handler if iOS revokes the task).
    private func runSilentPushSync(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Use a reference-type box so the expiration handler (background thread)
        // and the MainActor Task share the same identifier without a data race on
        // a captured `var`. Both closures read/write the box's `value` under
        // NSLock, preventing concurrent mutation.
        let taskBox = BackgroundTaskBox()
        taskBox.value = UIApplication.shared.beginBackgroundTask(withName: "SilentPushSync") {
            // Expiration handler runs on an arbitrary background thread.
            taskBox.endIfNeeded()
        }

        // If iOS declined to grant background time (low battery, throttling, etc.)
        // there is no point running the sync — we have no protected execution time.
        guard taskBox.value != .invalid else {
            completionHandler(.failed)
            return
        }

        // Tell iOS we handled the push within the 30s window. Real work
        // continues under the background-task assertion above.
        //
        // We always pass `.newData` here regardless of whether the eventual sync
        // finds 0 records. Ideally `.noData` would be sent for empty syncs so iOS
        // can calibrate push frequency, but we invoke `completionHandler` before
        // the sync finishes (to stay within the 30s deadline), so the record count
        // is not yet known. Deferring `completionHandler` until sync completion
        // risks the watchdog killing us — `.newData` is the safe trade-off.
        completionHandler(.newData)

        Task { @MainActor in
            // Reset state so a previous .success/.failure does not block this run
            // (runDeltaSync guards on .idle and resetState is only called from UI otherwise).
            SyncManager.shared.resetState()
            await SyncManager.shared.runDeltaSync()
            taskBox.endIfNeeded()
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
        let userInfo = notification.request.content.userInfo
        let type = userInfo["type"] as? String
        if type == "analysis_ready" {
            NotificationCenter.default.post(name: .analysisReady, object: nil)
        }
        // Omit .badge: the app is already in the foreground so applicationDidBecomeActive
        // won't fire again, which means a badge set here would not be cleared until the
        // next foreground transition.
        completionHandler([.banner, .sound])
    }

    /// Handle tap on a delivered notification.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String
        if type == "analysis_ready" {
            NotificationCenter.default.post(name: .analysisReady, object: nil)
        }

        // The backend may put the action either at the top level or nested under "data"
        // (FCM-style payload). Check both locations so iOS-side handling is resilient
        // to how the push is composed server-side.
        if AppDelegate.extractAction(from: userInfo) == "open_profile" {
            // Store as pending action/highlight to handle cold-start case where MainTabView
            // is not yet subscribed to NotificationCenter when the delegate fires.
            Task { @MainActor in
                AppDelegate.pendingAction = "open_profile"
                AppDelegate.pendingHighlightDOB = true
            }
            NotificationCenter.default.post(name: .openProfile, object: nil)
        }

        completionHandler()
    }

    /// Returns the `action` field from a push payload, supporting both
    /// top-level (`userInfo["action"]`) and nested (`userInfo["data"]["action"]`) shapes.
    /// Internal for unit testing.
    static func extractAction(from userInfo: [AnyHashable: Any]) -> String? {
        if let action = userInfo["action"] as? String {
            return action
        }
        let data = userInfo["data"] as? [AnyHashable: Any]
        return data?["action"] as? String
    }
}

extension Notification.Name {
    static let analysisReady = Notification.Name("com.healthlogsync.analysisReady")
    static let openProfile = Notification.Name("com.healthlogsync.openProfile")
    static let highlightDOBField = Notification.Name("com.healthlogsync.highlightDOBField")
}

/// Thread-safe wrapper for `UIBackgroundTaskIdentifier`.
/// Shared between the expiration handler (background thread) and the
/// MainActor Task in `runSilentPushSync` / `runInitialSync` to avoid a
/// data race on a captured `var`.
final class BackgroundTaskBox {
    private let lock = NSLock()
    private var identifier = UIBackgroundTaskIdentifier.invalid

    var value: UIBackgroundTaskIdentifier {
        get { lock.withLock { identifier } }
        set { lock.withLock { identifier = newValue } }
    }

    func endIfNeeded() {
        let taskID: UIBackgroundTaskIdentifier = lock.withLock {
            let current = identifier
            if current != .invalid {
                identifier = .invalid
            }
            return current
        }
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }
}

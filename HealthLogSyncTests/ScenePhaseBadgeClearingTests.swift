import XCTest
@testable import HealthLogSync

/// Regression tests for the app-icon badge not clearing when returning from background.
///
/// Root cause: In SwiftUI scene-based lifecycle (iOS 13+),
/// `UIApplicationDelegate.applicationDidBecomeActive` is called only on cold
/// launch (process start from suspended/terminated). Subsequent foreground
/// transitions fire scene callbacks instead.
///
/// Fix: `HealthLogSyncApp` observes `\.scenePhase` and calls
/// `UNUserNotificationCenter.setBadgeCount(0)` whenever the phase becomes
/// `.active`. `AppDelegate.applicationDidBecomeActive` is kept as a safety net
/// for the cold-launch path.
///
/// Full verification of the async `setBadgeCount(0)` call requires a live
/// simulator session; these unit tests document the structural contract.
final class ScenePhaseBadgeClearingTests: XCTestCase {
    /// Verifies that `AppDelegate` still contains `applicationDidBecomeActive`
    /// as a safety net for cold-launch badge clearing.
    func test_appDelegate_hasDidBecomeActiveImplementation() {
        let delegate = AppDelegate()
        // If the safety-net method is removed this line will not compile,
        // catching the regression at build time.
        delegate.applicationDidBecomeActive(UIApplication.shared)
        // No assertion needed — the goal is confirming the method exists
        // and does not crash synchronously.
    }

    /// Structural guard: `HealthLogSyncApp` must be the @main entry point.
    /// If someone renames or removes the type this test will not compile.
    func test_healthLogSyncApp_typeExists() {
        // HealthLogSyncApp conforms to App; instantiation is owned by the OS,
        // so we just verify the type is accessible from the test target.
        _ = HealthLogSyncApp.self
    }
}

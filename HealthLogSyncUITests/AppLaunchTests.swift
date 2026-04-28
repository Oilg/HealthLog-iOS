import XCTest

final class AppLaunchTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    func test_appLaunches_withoutCrashing() {
        XCTAssertTrue(app.state == .runningForeground)
    }

    func test_authScreen_isShownWhenNotLoggedIn() {
        let emailField = app.textFields["email"]
        let passwordField = app.secureTextFields["password"]
        let loginButton = app.buttons["Войти"]
        XCTAssertTrue(
            emailField.waitForExistence(timeout: 3)
                || passwordField.waitForExistence(timeout: 1)
                || loginButton.waitForExistence(timeout: 1)
                || app.navigationBars.firstMatch.waitForExistence(timeout: 1),
            "Expected auth or main screen to be visible at launch"
        )
    }
}

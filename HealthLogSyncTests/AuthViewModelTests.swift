import XCTest
@testable import HealthLogSync

@MainActor
final class AuthViewModelTests: XCTestCase {
    // MARK: - isPasswordVisible

    func test_isPasswordVisible_defaultsToFalse() {
        let viewModel = AuthViewModel()
        XCTAssertFalse(viewModel.isPasswordVisible)
    }

    func test_togglePasswordVisibility_flipsValue() {
        let viewModel = AuthViewModel()
        viewModel.togglePasswordVisibility()
        XCTAssertTrue(viewModel.isPasswordVisible)
        viewModel.togglePasswordVisibility()
        XCTAssertFalse(viewModel.isPasswordVisible)
    }

    func test_toggleMode_resetsPasswordVisibility() {
        let viewModel = AuthViewModel()
        viewModel.isPasswordVisible = true
        viewModel.toggleMode()
        XCTAssertFalse(viewModel.isPasswordVisible)
        XCTAssertTrue(viewModel.isRegistering)
    }

    func test_toggleMode_resetsPasswordVisibility_whenSwitchingBackToLogin() {
        let viewModel = AuthViewModel()
        viewModel.isRegistering = true
        viewModel.isPasswordVisible = true
        viewModel.toggleMode()
        XCTAssertFalse(viewModel.isPasswordVisible)
        XCTAssertFalse(viewModel.isRegistering)
    }

    func test_toggleMode_clearsErrorMessage() {
        let viewModel = AuthViewModel()
        viewModel.errorMessage = "boom"
        viewModel.toggleMode()
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - isSubmitDisabled

    func test_isSubmitDisabled_whenEmailEmpty() {
        let viewModel = AuthViewModel()
        viewModel.password = "pass"
        XCTAssertTrue(viewModel.isSubmitDisabled)
    }

    func test_isSubmitDisabled_whenPasswordEmpty() {
        let viewModel = AuthViewModel()
        viewModel.email = "a@b.c"
        XCTAssertTrue(viewModel.isSubmitDisabled)
    }

    func test_isSubmitDisabled_loginReadyWhenEmailAndPasswordFilled() {
        let viewModel = AuthViewModel()
        viewModel.email = "a@b.c"
        viewModel.password = "pass"
        XCTAssertFalse(viewModel.isSubmitDisabled)
    }
}

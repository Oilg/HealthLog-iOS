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

    // MARK: - passwordHint

    func test_passwordHint_nilWhenNotRegistering() {
        let viewModel = AuthViewModel()
        viewModel.isRegistering = false
        viewModel.password = "123"
        XCTAssertNil(viewModel.passwordHint)
    }

    func test_passwordHint_nilWhenPasswordEmpty() {
        let viewModel = AuthViewModel()
        viewModel.isRegistering = true
        viewModel.password = ""
        XCTAssertNil(viewModel.passwordHint)
    }

    func test_passwordHint_nilWhenPasswordLongEnough() {
        let viewModel = AuthViewModel()
        viewModel.isRegistering = true
        viewModel.password = "12345678"
        XCTAssertNil(viewModel.passwordHint)
    }

    func test_passwordHint_presentWhenPasswordTooShort() {
        let viewModel = AuthViewModel()
        viewModel.isRegistering = true
        viewModel.password = "1234567"
        XCTAssertNotNil(viewModel.passwordHint)
        XCTAssertTrue(viewModel.passwordHint!.contains("8"))
    }

    // MARK: - Local validation

    func test_submit_setsErrorWhenFirstNameEmpty() async {
        let viewModel = AuthViewModel()
        viewModel.isRegistering = true
        viewModel.firstName = "   "
        viewModel.lastName = "Doe"
        viewModel.email = "a@b.c"
        viewModel.password = "12345678"
        viewModel.phone = "+7999"
        let result = await viewModel.submit()
        XCTAssertFalse(result)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage!.lowercased().contains("имя"))
    }

    func test_submit_setsErrorWhenLastNameEmpty() async {
        let viewModel = AuthViewModel()
        viewModel.isRegistering = true
        viewModel.firstName = "John"
        viewModel.lastName = ""
        viewModel.email = "a@b.c"
        viewModel.password = "12345678"
        viewModel.phone = "+7999"
        let result = await viewModel.submit()
        XCTAssertFalse(result)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage!.lowercased().contains("фамили"))
    }

    func test_submit_setsErrorWhenPasswordTooShort() async {
        let viewModel = AuthViewModel()
        viewModel.isRegistering = true
        viewModel.firstName = "John"
        viewModel.lastName = "Doe"
        viewModel.email = "a@b.c"
        viewModel.password = "1234"
        viewModel.phone = "+7999"
        let result = await viewModel.submit()
        XCTAssertFalse(result)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage!.contains("8"))
    }
}

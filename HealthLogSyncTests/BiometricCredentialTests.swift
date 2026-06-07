import LocalAuthentication
import XCTest
@testable import HealthLogSync

final class BiometricCredentialTests: XCTestCase {
    private let keychain = KeychainManager.shared

    override func setUp() {
        super.setUp()
        keychain.deleteBiometricCredentials()
    }

    override func tearDown() {
        keychain.deleteBiometricCredentials()
        super.tearDown()
    }

    // MARK: - hasBiometricCredentials

    func test_hasBiometricCredentials_falseWhenNothingSaved() {
        XCTAssertFalse(keychain.hasBiometricCredentials)
    }

    // MARK: - saveBiometricCredentials / biometricCredentials

    func test_biometricCredentials_nilWhenNothingSaved() {
        XCTAssertNil(keychain.biometricCredentials(context: LAContext()))
    }

    func test_deleteBiometricCredentials_removesStoredValues() {
        // Insert plain items directly via save() to avoid biometry gate in tests
        keychain.save("user@example.com", for: .biometricEmail)
        keychain.save("s3cr3t", for: .biometricPassword)
        keychain.deleteBiometricCredentials()
        XCTAssertNil(keychain.get(.biometricEmail))
        XCTAssertNil(keychain.get(.biometricPassword))
    }

    func test_biometricCredentials_returnsValuesStoredViaPlainSave() {
        keychain.save("alice@example.com", for: .biometricEmail)
        keychain.save("hunter2", for: .biometricPassword)
        let creds = keychain.biometricCredentials(context: LAContext())
        XCTAssertEqual(creds?.email, "alice@example.com")
        XCTAssertEqual(creds?.password, "hunter2")
    }

    func test_hasBiometricCredentials_trueAfterStoringViaPlainSave() {
        keychain.save("bob@example.com", for: .biometricEmail)
        keychain.save("pass123", for: .biometricPassword)
        // Also store the marker that saveBiometricCredentials() would write.
        keychain.save("1", for: .biometricCredentialsSaved)
        XCTAssertTrue(keychain.hasBiometricCredentials)
    }

    func test_deleteBiometricCredentials_makeHasBiometricCredentialsFalse() {
        keychain.save("eve@example.com", for: .biometricEmail)
        keychain.save("pass", for: .biometricPassword)
        keychain.save("1", for: .biometricCredentialsSaved)
        keychain.deleteBiometricCredentials()
        XCTAssertFalse(keychain.hasBiometricCredentials)
    }

    // MARK: - AuthViewModel biometric helpers

    @MainActor
    func test_authViewModel_saveCredentialsForBiometrics_storesValues() {
        let viewModel = AuthViewModel()
        viewModel.email = "test@example.com"
        viewModel.password = "mypassword"
        viewModel.saveCredentialsForBiometrics()
        // Use a plain LAContext — items saved via saveBiometricCredentials() have .biometryAny
        // access control, but in the simulator the keychain does not enforce biometry so this
        // still returns the stored values.
        let creds = keychain.biometricCredentials(context: LAContext())
        XCTAssertEqual(creds?.email, "test@example.com")
        XCTAssertEqual(creds?.password, "mypassword")
    }

    @MainActor
    func test_authViewModel_isBiometricAvailable_falseWhenNoCredentials() {
        // No stored credentials → should be false regardless of device biometry
        let viewModel = AuthViewModel()
        XCTAssertFalse(viewModel.isBiometricAvailable)
    }
}

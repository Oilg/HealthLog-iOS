import XCTest
@testable import HealthLogSync

final class ValidationErrorParsingTests: XCTestCase {
    // MARK: - ValidationErrorItem decoding

    func test_decodeValidationErrorArray_passwordTooShort() throws {
        let json = """
        [{"type":"string_too_short","loc":["body","password"],"msg":"String should have at least 8 characters","input":"123qwe","ctx":{"min_length":8}}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([ValidationErrorItem].self, from: json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, "string_too_short")
        XCTAssertEqual(items[0].fieldName, "password")
    }

    func test_decodeValidationErrorArray_mixedLocSegments() throws {
        let json = """
        [{"type":"missing","loc":["body","first_name"],"msg":"Field required","input":null}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([ValidationErrorItem].self, from: json)
        XCTAssertEqual(items[0].fieldName, "first_name")
    }

    func test_locSegment_skipsBodyPrefix() throws {
        let json = """
        [{"type":"value_error","loc":["body","email"],"msg":"value is not a valid email address","input":"bad"}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([ValidationErrorItem].self, from: json)
        XCTAssertEqual(items[0].fieldName, "email")
        XCTAssertFalse(items[0].fieldName.contains("body"))
    }

    func test_locSegment_intIndexInLoc() throws {
        // Pydantic sometimes includes integer indices in loc
        let json = """
        [{"type":"string_too_short","loc":["body","records",0,"value"],"msg":"too short","input":"x"}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([ValidationErrorItem].self, from: json)
        XCTAssertEqual(items[0].fieldName, "records.0.value")
    }
}

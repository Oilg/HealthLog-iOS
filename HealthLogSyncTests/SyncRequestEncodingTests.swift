import XCTest
@testable import HealthLogSync

final class SyncRequestEncodingTests: XCTestCase {
    private let encoder: JSONEncoder = .init()

    func test_syncRequest_encodesAppVersion() throws {
        let request = SyncRequest(
            syncFrom: "2024-01-01T00:00:00Z",
            syncTo: "2024-01-02T00:00:00Z",
            records: [],
            appVersion: "2.3.1"
        )
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["app_version"] as? String, "2.3.1")
    }

    func test_syncRequest_encodesNilAppVersionAsNull() throws {
        let request = SyncRequest(
            syncFrom: "2024-01-01T00:00:00Z",
            syncTo: "2024-01-02T00:00:00Z",
            records: [],
            appVersion: nil
        )
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // nil optional is omitted or null — either way app_version should not be a non-null string
        if let version = json?["app_version"] {
            XCTAssertTrue(version is NSNull, "Expected null for nil appVersion, got \(version)")
        }
    }

    func test_syncRequest_encodesSyncFromAndTo() throws {
        let request = SyncRequest(
            syncFrom: "2024-01-01T00:00:00Z",
            syncTo: "2024-01-02T00:00:00Z",
            records: [],
            appVersion: nil
        )
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["sync_from"] as? String, "2024-01-01T00:00:00Z")
        XCTAssertEqual(json?["sync_to"] as? String, "2024-01-02T00:00:00Z")
    }
}

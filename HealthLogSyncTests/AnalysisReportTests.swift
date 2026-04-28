import XCTest
@testable import HealthLogSync

final class AnalysisReportTests: XCTestCase {

    // MARK: - Decoding

    func test_decoding_withPeriodDates() throws {
        let json = """
        {
            "analyzed_at": "2026-04-28T10:00:00",
            "period_from": "2026-04-21T00:00:00",
            "period_to":   "2026-04-28T10:00:00",
            "risks": []
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(AnalysisReport.self, from: json)
        XCTAssertNotNil(report.periodFrom)
        XCTAssertNotNil(report.periodTo)
    }

    func test_decoding_withoutPeriodDates_yieldsNil() throws {
        let json = """
        {
            "analyzed_at": "2026-04-28T10:00:00",
            "risks": []
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(AnalysisReport.self, from: json)
        XCTAssertNil(report.periodFrom)
        XCTAssertNil(report.periodTo)
    }

    func test_decoding_emptyRisks() throws {
        let report = try decode(risks: "[]")
        XCTAssertTrue(report.risks.isEmpty)
    }

    func test_decoding_multipleRisks_preservesOrder() throws {
        let report = try decode(risks: """
        [
            {"condition":"obesity_risk","severity":"moderate","confidence":0.9,"interpretation":"A"},
            {"condition":"cardiovascular_risk","severity":"high","confidence":1.0,"interpretation":"B"}
        ]
        """)
        XCTAssertEqual(report.risks.count, 2)
        XCTAssertEqual(report.risks[0].type, "obesity_risk")
        XCTAssertEqual(report.risks[1].type, "cardiovascular_risk")
    }

    func test_decoding_riskFieldsMappedCorrectly() throws {
        let report = try decode(risks: """
        [{"condition":"sedentary_lifestyle_risk","severity":"high","confidence":1.0,"interpretation":"Малоподвижный"}]
        """)
        let risk = try XCTUnwrap(report.risks.first)
        XCTAssertEqual(risk.type, "sedentary_lifestyle_risk")
        XCTAssertEqual(risk.severity, "high")
        XCTAssertEqual(risk.confidence, 1.0, accuracy: 0.001)
        XCTAssertEqual(risk.description, "Малоподвижный")
    }

    func test_id_isAnalyzedAt() throws {
        let report = try decode()
        XCTAssertEqual(report.id, report.analyzedAt)
    }

    // MARK: - Helpers

    private func decode(risks: String = "[]") throws -> AnalysisReport {
        let json = """
        {
            "analyzed_at": "2026-04-28T10:00:00",
            "period_from": "2026-04-21T00:00:00",
            "period_to":   "2026-04-28T10:00:00",
            "risks": \(risks)
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(AnalysisReport.self, from: json)
    }
}

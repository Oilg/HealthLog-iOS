import XCTest
@testable import HealthLogSync

final class RiskItemTests: XCTestCase {

    // MARK: - JSON Decoding

    func test_decoding_mapsConditionToType() throws {
        let item = try decode(condition: "obesity_risk", interpretation: "Подозрение на ожирение")
        XCTAssertEqual(item.type, "obesity_risk")
        XCTAssertEqual(item.description, "Подозрение на ожирение")
    }

    func test_decoding_mapsSeverityAndConfidence() throws {
        let item = try decode(severity: "high", confidence: 1.0)
        XCTAssertEqual(item.severity, "high")
        XCTAssertEqual(item.confidence, 1.0, accuracy: 0.001)
    }

    func test_decoding_lowConfidence() throws {
        let item = try decode(confidence: 0.4)
        XCTAssertEqual(item.confidence, 0.4, accuracy: 0.001)
    }

    func test_id_isType() throws {
        let item = try decode(condition: "cardiovascular_risk")
        XCTAssertEqual(item.id, "cardiovascular_risk")
    }

    // MARK: - localizedName

    func test_localizedName_allKnownTypes() throws {
        let cases: [(String, String)] = [
            ("overload_recovery_risk",     "Перегрузка и недовосстановление"),
            ("noise_exposure_risk",        "Шумовое воздействие"),
            ("obesity_risk",               "Риск ожирения"),
            ("sedentary_lifestyle_risk",   "Малоподвижный образ жизни"),
            ("insufficient_activity_risk", "Недостаточная активность"),
            ("cardiometabolic_risk",       "Кардиометаболический профиль"),
            ("metabolic_syndrome_risk",    "Метаболический синдром"),
            ("cardiovascular_risk",        "Сердечно-сосудистый риск"),
            ("recovery_inefficiency_risk", "Неэффективное восстановление"),
        ]
        for (type, expected) in cases {
            let item = try decode(condition: type)
            XCTAssertEqual(item.localizedName, expected, "localizedName для \(type)")
        }
    }

    func test_localizedName_unknownType_fallsBackToCapitalized() throws {
        let item = try decode(condition: "some_new_risk_type")
        XCTAssertEqual(item.localizedName, "Some New Risk Type")
    }

    // MARK: - severityLabel

    func test_severityLabel_high() throws {
        XCTAssertEqual(try decode(severity: "high").severityLabel, "Высокий")
    }

    func test_severityLabel_moderate() throws {
        XCTAssertEqual(try decode(severity: "moderate").severityLabel, "Средний")
    }

    func test_severityLabel_low() throws {
        XCTAssertEqual(try decode(severity: "low").severityLabel, "Низкий")
    }

    func test_severityLabel_unknownValue_defaultsToLow() throws {
        XCTAssertEqual(try decode(severity: "critical").severityLabel, "Низкий")
    }

    // MARK: - severityColor

    func test_severityColor_high_isRed() throws {
        XCTAssertEqual(try decode(severity: "high").severityColor, .red)
    }

    func test_severityColor_moderate_isOrange() throws {
        XCTAssertEqual(try decode(severity: "moderate").severityColor, .orange)
    }

    func test_severityColor_low_isYellow() throws {
        XCTAssertEqual(try decode(severity: "low").severityColor, .yellow)
    }

    func test_severityColor_unknownValue_defaultsToYellow() throws {
        XCTAssertEqual(try decode(severity: "info").severityColor, .yellow)
    }

    // MARK: - Helpers

    private func decode(
        condition: String = "obesity_risk",
        severity: String = "moderate",
        confidence: Double = 0.9,
        interpretation: String = "Test"
    ) throws -> RiskItem {
        let json = """
        {
            "condition": "\(condition)",
            "severity": "\(severity)",
            "confidence": \(confidence),
            "interpretation": "\(interpretation)"
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(RiskItem.self, from: json)
    }
}

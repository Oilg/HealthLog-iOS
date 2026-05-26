import XCTest
@testable import HealthLogSync

final class WeeklyProgressTests: XCTestCase {
    // MARK: - Decoding

    func test_decoding_fullResponse() throws {
        let jsonString = """
        {
            "current_period_from": "2026-05-19T12:00:00",
            "current_period_to":   "2026-05-26T12:00:00",
            "previous_period_from": "2026-05-12T12:00:00",
            "previous_period_to":   "2026-05-19T12:00:00",
            "has_previous": true,
            "items": [
                {
                    "condition": "tachycardia_risk",
                    "label": "Тахикардия",
                    "current_severity": "moderate",
                    "previous_severity": "low",
                    "severity_delta": 1,
                    "direction": "worsened",
                    "current_confidence": 0.7,
                    "previous_confidence": 0.5
                }
            ]
        }
        """
        let json = Data(jsonString.utf8)

        let response = try JSONDecoder().decode(WeeklyProgressResponse.self, from: json)
        XCTAssertTrue(response.hasPrevious)
        XCTAssertEqual(response.items.count, 1)

        let item = response.items[0]
        XCTAssertEqual(item.condition, "tachycardia_risk")
        XCTAssertEqual(item.label, "Тахикардия")
        XCTAssertEqual(item.currentSeverity, "moderate")
        XCTAssertEqual(item.previousSeverity, "low")
        XCTAssertEqual(item.severityDelta, 1)
        XCTAssertEqual(item.direction, "worsened")
        XCTAssertEqual(item.currentConfidence, 0.7)
        XCTAssertEqual(item.previousConfidence, 0.5)
    }

    func test_decoding_emptyItems_hasPreviousFalse() throws {
        let jsonString = """
        {
            "current_period_from": null,
            "current_period_to":   null,
            "previous_period_from": null,
            "previous_period_to":   null,
            "has_previous": false,
            "items": []
        }
        """
        let json = Data(jsonString.utf8)

        let response = try JSONDecoder().decode(WeeklyProgressResponse.self, from: json)
        XCTAssertFalse(response.hasPrevious)
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertNil(response.currentPeriodFrom)
    }

    func test_decoding_nullConfidence() throws {
        let jsonString = """
        {
            "condition": "fall_risk",
            "label": "Устойчивость ходьбы",
            "current_severity": "none",
            "previous_severity": "high",
            "severity_delta": -3,
            "direction": "improved",
            "current_confidence": null,
            "previous_confidence": null
        }
        """
        let json = Data(jsonString.utf8)

        let item = try JSONDecoder().decode(WeeklyProgressItem.self, from: json)
        XCTAssertNil(item.currentConfidence)
        XCTAssertNil(item.previousConfidence)
    }

    // MARK: - Direction symbol / color

    func test_directionSymbol_improvedWorsenedUnchanged() {
        XCTAssertEqual(makeItem(direction: "improved").directionSymbol, "arrow.down.right.circle.fill")
        XCTAssertEqual(makeItem(direction: "worsened").directionSymbol, "arrow.up.right.circle.fill")
        XCTAssertEqual(makeItem(direction: "unchanged").directionSymbol, "minus.circle.fill")
    }

    func test_directionTitle_localizedRussian() {
        XCTAssertEqual(makeItem(direction: "improved").directionTitle, "Улучшение")
        XCTAssertEqual(makeItem(direction: "worsened").directionTitle, "Ухудшение")
        XCTAssertEqual(makeItem(direction: "unchanged").directionTitle, "Без изменений")
    }

    // MARK: - Delta text

    func test_deltaText_zero_returnsDash() {
        XCTAssertEqual(makeItem(severityDelta: 0).deltaText, "—")
    }

    func test_deltaText_positive_returnsPlusSign() {
        XCTAssertEqual(makeItem(severityDelta: 2).deltaText, "+2")
    }

    func test_deltaText_negative_returnsMinusSign() {
        // U+2212 minus sign, not hyphen.
        XCTAssertEqual(makeItem(severityDelta: -3).deltaText, "−3")
    }

    // MARK: - Severity labels

    func test_severityLabel_known() {
        XCTAssertEqual(makeItem(currentSeverity: "high").currentSeverityLabel, "Высокий")
        XCTAssertEqual(makeItem(currentSeverity: "moderate").currentSeverityLabel, "Средний")
        XCTAssertEqual(makeItem(currentSeverity: "low").currentSeverityLabel, "Низкий")
        XCTAssertEqual(makeItem(currentSeverity: "none").currentSeverityLabel, "Нет")
    }

    func test_severityLabel_unknown_returnsNet() {
        XCTAssertEqual(makeItem(currentSeverity: "weird").currentSeverityLabel, "Нет")
    }

    // MARK: - Identifiable conformance

    func test_id_equalsCondition() {
        let item = makeItem(condition: "obesity_risk")
        XCTAssertEqual(item.id, "obesity_risk")
    }

    // MARK: - Empty state logic (fix #2)

    func test_emptyItems_hasPreviousFalse_noHistory() throws {
        let json = Data("""
        {
            "current_period_from": null, "current_period_to": null,
            "previous_period_from": null, "previous_period_to": null,
            "has_previous": false, "items": []
        }
        """.utf8)
        let response = try JSONDecoder().decode(WeeklyProgressResponse.self, from: json)
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertFalse(response.hasPrevious)
    }

    func test_emptyItems_hasPreviousTrue_allClear() throws {
        let json = Data("""
        {
            "current_period_from": "2026-05-19T12:00:00",
            "current_period_to": "2026-05-26T12:00:00",
            "previous_period_from": "2026-05-12T12:00:00",
            "previous_period_to": "2026-05-19T12:00:00",
            "has_previous": true, "items": []
        }
        """.utf8)
        let response = try JSONDecoder().decode(WeeklyProgressResponse.self, from: json)
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertTrue(response.hasPrevious)
    }

    // MARK: - Helpers

    private func makeItem(
        condition: String = "tachycardia_risk",
        label: String = "Тахикардия",
        currentSeverity: String = "moderate",
        previousSeverity: String = "low",
        severityDelta: Int = 1,
        direction: String = "worsened"
    ) -> WeeklyProgressItem {
        WeeklyProgressItem(
            condition: condition,
            label: label,
            currentSeverity: currentSeverity,
            previousSeverity: previousSeverity,
            severityDelta: severityDelta,
            direction: direction,
            currentConfidence: nil,
            previousConfidence: nil
        )
    }
}

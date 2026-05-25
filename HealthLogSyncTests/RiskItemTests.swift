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
        let item = try decode(condition: "cardiovascular_obesity_risk")
        XCTAssertEqual(item.id, "cardiovascular_obesity_risk")
    }

    // MARK: - localizedName

    func test_localizedName_allKnownTypes() throws {
        let cases: [(String, String)] = [
            ("sleep_apnea_risk", "Апноэ сна"),
            ("tachycardia_risk", "Тахикардия"),
            ("bradycardia_risk", "Брадикардия"),
            ("irregular_rhythm_risk", "Нерегулярный сердечный ритм"),
            ("atrial_fibrillation_risk", "Фибрилляция предсердий"),
            ("hypertension_risk", "Повышенное артериальное давление"),
            ("hypotension_risk", "Пониженное артериальное давление"),
            ("low_oxygen_saturation_risk", "Снижение кислорода в крови"),
            ("temperature_shift_risk", "Температурный сдвиг / лихорадка"),
            ("illness_onset_risk", "Начало простуды / воспалительного процесса"),
            ("vo2max_decline_risk", "Снижение кардиофитнеса"),
            ("hrr_decline_risk", "Ухудшение восстановления после нагрузки"),
            ("overload_recovery_risk", "Перегрузка и недовосстановление"),
            ("walking_tolerance_decline_risk", "Ухудшение переносимости нагрузки"),
            ("walking_fitness_decline_risk", "Снижение функциональной ходьбы"),
            ("respiratory_function_decline_risk", "Ухудшение дыхательной функции"),
            ("fall_risk", "Риск падений"),
            ("noise_exposure_risk", "Шумовое воздействие"),
            ("overweight_risk", "Избыточная масса тела"),
            ("obesity_risk", "Риск ожирения"),
            ("high_body_fat_risk", "Повышенный процент жира"),
            ("abdominal_obesity_risk", "Абдоминальное ожирение"),
            ("lean_mass_decline_risk", "Снижение безжировой массы"),
            ("weight_trend_risk", "Неблагоприятная динамика веса"),
            ("fat_mass_trend_risk", "Неблагоприятная динамика жировой массы"),
            ("sedentary_lifestyle_risk", "Малоподвижный образ жизни"),
            ("insufficient_activity_risk", "Недостаточная активность"),
            ("cardiometabolic_profile_risk", "Кардиометаболический профиль"),
            ("metabolic_syndrome_risk", "Метаболический синдром"),
            ("cardiovascular_obesity_risk", "Сердечно-сосудистый риск"),
            ("fitness_weight_gain_risk", "Ухудшение физической формы"),
            ("recovery_obesity_risk", "Неэффективное восстановление"),
            ("body_composition_trend_risk", "Неблагоприятный тренд состава тела"),
            ("menstrual_cycle_start_forecast", "Прогноз начала менструации"),
            ("menstrual_cycle_delay_risk", "Возможная задержка менструации"),
            ("ovulation_window_forecast", "Окно вероятной овуляции"),
            ("menstrual_irregularity_risk", "Нерегулярность менструального цикла"),
            ("atypical_menstrual_bleeding_risk", "Атипичные менструальные кровотечения"),
            ("menstrual_start_forecast_with_temp", "Уточнённый прогноз менструации"),
            ("ovulation_forecast_with_temp", "Уточнённый прогноз овуляции"),
        ]
        for (type, expected) in cases {
            let item = try decode(condition: type)
            XCTAssertEqual(item.localizedName, expected, "localizedName для \(type)")
        }
    }

    func test_localizedName_unknownType_fallsBackToSpaces() throws {
        let item = try decode(condition: "some_new_risk_type")
        XCTAssertEqual(item.localizedName, "some new risk type")
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
        """
        return try JSONDecoder().decode(RiskItem.self, from: Data(json.utf8))
    }
}

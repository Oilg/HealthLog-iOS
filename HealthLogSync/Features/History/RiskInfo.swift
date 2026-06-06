import Foundation

/// Тип карточки риска. Разделение нужно, чтобы UI и копирайтинг
/// прогнозов (нейтральный тон, без обязательного визита к врачу) отличались
/// от рисков (медицинская рекомендация, обязательная фраза для врача).
enum RiskInfoKind {
    /// Обнаруженное отклонение или потенциальный риск.
    case risk
    /// Информационный прогноз (например, окно овуляции). Без тревожной риторики.
    case forecast
}

/// Описание риска или прогноза для экрана `RiskDetailView`.
///
/// Содержит весь контент, который пользователь видит после того, как
/// серверный детектор обнаружил паттерн в данных Apple Health.
struct RiskInfo: Equatable {
    let kind: RiskInfoKind
    /// Объяснение простым языком (2–3 предложения).
    let explanation: String
    /// Конкретный профиль врача — не общий «терапевт» для всего.
    let doctorType: String
    /// Конкретные шаги пользователя.
    let actions: [String]
    /// Готовая фраза для приёма у врача от первого лица.
    /// Для прогнозов может быть `nil` — тогда блок «Что сказать на приёме» скрывается.
    let doctorVisitReason: String?
    /// Релевантные анализы и инструментальные исследования.
    /// Для прогнозов может быть пустым.
    let testsToOrder: [String]
    /// Типы данных Apple Health, которые использует детектор.
    let healthDataTypes: [String]

    init(
        kind: RiskInfoKind = .risk,
        explanation: String,
        doctorType: String,
        actions: [String],
        doctorVisitReason: String?,
        testsToOrder: [String],
        healthDataTypes: [String]
    ) {
        self.kind = kind
        self.explanation = explanation
        self.doctorType = doctorType
        self.actions = actions
        self.doctorVisitReason = doctorVisitReason
        self.testsToOrder = testsToOrder
        self.healthDataTypes = healthDataTypes
    }

    /// Единый источник истины: все типы рисков и прогнозов, для которых
    /// в приложении есть подробная карточка. Используется тестами на полноту
    /// каталога и согласованность с `RiskItem.localizedName`.
    static let knownTypes: [String] = [
        // Сердечно-сосудистые
        "sleep_apnea_risk",
        "tachycardia_risk",
        "bradycardia_risk",
        "irregular_rhythm_risk",
        "atrial_fibrillation_risk",
        "hypertension_risk",
        "hypotension_risk",
        // Метаболические / дыхательные
        "low_oxygen_saturation_risk",
        "temperature_shift_risk",
        "illness_onset_risk",
        "respiratory_function_decline_risk",
        // Фитнес и физическая форма
        "vo2max_decline_risk",
        "hrr_decline_risk",
        "overload_recovery_risk",
        "walking_tolerance_decline_risk",
        "walking_fitness_decline_risk",
        "fall_risk",
        "insufficient_activity_risk",
        "sedentary_lifestyle_risk",
        "cardiometabolic_profile_risk",
        // Состав тела
        "obesity_risk",
        "overweight_risk",
        "high_body_fat_risk",
        "abdominal_obesity_risk",
        "lean_mass_decline_risk",
        "weight_trend_risk",
        "fat_mass_trend_risk",
        "fitness_weight_gain_risk",
        "body_composition_trend_risk",
        "metabolic_syndrome_risk",
        "cardiovascular_obesity_risk",
        "recovery_obesity_risk",
        // Менструальный цикл
        "menstrual_cycle_start_forecast",
        "menstrual_cycle_delay_risk",
        "ovulation_window_forecast",
        "menstrual_irregularity_risk",
        "atypical_menstrual_bleeding_risk",
        "menstrual_start_forecast_with_temp",
        "ovulation_forecast_with_temp",
        // Окружение
        "noise_exposure_risk",
    ]
}

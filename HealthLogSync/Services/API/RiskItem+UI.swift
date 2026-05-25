import SwiftUI

extension RiskItem {
    var localizedName: String {
        switch type {
        case "sleep_apnea_risk": return "Апноэ сна"
        case "tachycardia_risk": return "Тахикардия"
        case "bradycardia_risk": return "Брадикардия"
        case "irregular_rhythm_risk": return "Нерегулярный сердечный ритм"
        case "atrial_fibrillation_risk": return "Фибрилляция предсердий"
        case "hypertension_risk": return "Повышенное артериальное давление"
        case "hypotension_risk": return "Пониженное артериальное давление"
        case "low_oxygen_saturation_risk": return "Снижение кислорода в крови"
        case "temperature_shift_risk": return "Температурный сдвиг / лихорадка"
        case "illness_onset_risk": return "Начало простуды / воспалительного процесса"
        case "vo2max_decline_risk": return "Снижение кардиофитнеса"
        case "hrr_decline_risk": return "Ухудшение восстановления после нагрузки"
        case "overload_recovery_risk": return "Перегрузка и недовосстановление"
        case "walking_tolerance_decline_risk": return "Ухудшение переносимости нагрузки"
        case "walking_fitness_decline_risk": return "Снижение функциональной ходьбы"
        case "respiratory_function_decline_risk": return "Ухудшение дыхательной функции"
        case "fall_risk": return "Риск падений"
        case "noise_exposure_risk": return "Шумовое воздействие"
        case "overweight_risk": return "Избыточная масса тела"
        case "obesity_risk": return "Риск ожирения"
        case "high_body_fat_risk": return "Повышенный процент жира"
        case "abdominal_obesity_risk": return "Абдоминальное ожирение"
        case "lean_mass_decline_risk": return "Снижение безжировой массы"
        case "weight_trend_risk": return "Неблагоприятная динамика веса"
        case "fat_mass_trend_risk": return "Неблагоприятная динамика жировой массы"
        case "sedentary_lifestyle_risk": return "Малоподвижный образ жизни"
        case "insufficient_activity_risk": return "Недостаточная активность"
        case "cardiometabolic_profile_risk": return "Кардиометаболический профиль"
        case "metabolic_syndrome_risk": return "Метаболический синдром"
        case "cardiovascular_obesity_risk": return "Сердечно-сосудистый риск"
        case "fitness_weight_gain_risk": return "Ухудшение физической формы"
        case "recovery_obesity_risk": return "Неэффективное восстановление"
        case "body_composition_trend_risk": return "Неблагоприятный тренд состава тела"
        case "menstrual_cycle_start_forecast": return "Прогноз начала менструации"
        case "menstrual_cycle_delay_risk": return "Возможная задержка менструации"
        case "ovulation_window_forecast": return "Окно вероятной овуляции"
        case "menstrual_irregularity_risk": return "Нерегулярность менструального цикла"
        case "atypical_menstrual_bleeding_risk": return "Атипичные менструальные кровотечения"
        case "menstrual_start_forecast_with_temp": return "Уточнённый прогноз менструации"
        case "ovulation_forecast_with_temp": return "Уточнённый прогноз овуляции"
        default: return type.replacingOccurrences(of: "_", with: " ")
        }
    }

    var severityColor: Color {
        switch severity {
        case "high": return .red
        case "moderate": return .orange
        default: return .yellow
        }
    }

    var severityLabel: String {
        switch severity {
        case "high": return "Высокий"
        case "moderate": return "Средний"
        default: return "Низкий"
        }
    }
}

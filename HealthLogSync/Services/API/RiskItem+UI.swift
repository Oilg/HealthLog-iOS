import SwiftUI

extension RiskItem {
    var localizedName: String {
        switch type {
        case "overload_recovery_risk":   return "Перегрузка и недовосстановление"
        case "noise_exposure_risk":      return "Шумовое воздействие"
        case "obesity_risk":             return "Риск ожирения"
        case "sedentary_lifestyle_risk": return "Малоподвижный образ жизни"
        case "insufficient_activity_risk": return "Недостаточная активность"
        case "cardiometabolic_risk":     return "Кардиометаболический профиль"
        case "metabolic_syndrome_risk":  return "Метаболический синдром"
        case "cardiovascular_risk":      return "Сердечно-сосудистый риск"
        case "recovery_inefficiency_risk": return "Неэффективное восстановление"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var severityColor: Color {
        switch severity {
        case "high":     return .red
        case "moderate": return .orange
        default:         return .yellow
        }
    }

    var severityLabel: String {
        switch severity {
        case "high":     return "Высокий"
        case "moderate": return "Средний"
        default:         return "Низкий"
        }
    }
}

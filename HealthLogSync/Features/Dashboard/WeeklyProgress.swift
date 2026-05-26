import Foundation
import SwiftUI

// MARK: - API model

struct WeeklyProgressItem: Decodable, Identifiable, Equatable {
    var id: String {
        condition
    }

    let condition: String
    let label: String
    let currentSeverity: String
    let previousSeverity: String
    let severityDelta: Int
    let direction: String
    let currentConfidence: Double?
    let previousConfidence: Double?

    enum CodingKeys: String, CodingKey {
        case condition
        case label
        case currentSeverity = "current_severity"
        case previousSeverity = "previous_severity"
        case severityDelta = "severity_delta"
        case direction
        case currentConfidence = "current_confidence"
        case previousConfidence = "previous_confidence"
    }
}

struct WeeklyProgressResponse: Decodable, Equatable {
    let currentPeriodFrom: String?
    let currentPeriodTo: String?
    let previousPeriodFrom: String?
    let previousPeriodTo: String?
    let hasPrevious: Bool
    let items: [WeeklyProgressItem]

    enum CodingKeys: String, CodingKey {
        case currentPeriodFrom = "current_period_from"
        case currentPeriodTo = "current_period_to"
        case previousPeriodFrom = "previous_period_from"
        case previousPeriodTo = "previous_period_to"
        case hasPrevious = "has_previous"
        case items
    }
}

// MARK: - UI helpers

extension WeeklyProgressItem {
    /// SF Symbol for the trend arrow.
    var directionSymbol: String {
        switch direction {
        case "improved": return "arrow.down.right.circle.fill"
        case "worsened": return "arrow.up.right.circle.fill"
        default: return "minus.circle.fill"
        }
    }

    /// Color: green = improved, red = worsened, gray = unchanged.
    /// Note: for all detectors lower severity means better, so improved -> green.
    var directionColor: Color {
        switch direction {
        case "improved": return .green
        case "worsened": return .red
        default: return .secondary
        }
    }

    /// Russian text like "Стало лучше", "Ухудшилось", "Без изменений".
    var directionTitle: String {
        switch direction {
        case "improved": return "Улучшение"
        case "worsened": return "Ухудшение"
        default: return "Без изменений"
        }
    }

    /// Short formatted delta: "−2", "+1", or "—" for zero.
    var deltaText: String {
        if severityDelta == 0 { return "—" }
        let sign = severityDelta > 0 ? "+" : "−"
        return "\(sign)\(abs(severityDelta))"
    }

    var currentSeverityLabel: String {
        Self.severityLabel(severity: currentSeverity)
    }

    var previousSeverityLabel: String {
        Self.severityLabel(severity: previousSeverity)
    }

    private static func severityLabel(severity: String) -> String {
        switch severity {
        case "high": return "Высокий"
        case "moderate": return "Средний"
        case "low": return "Низкий"
        default: return "Нет"
        }
    }
}

// MARK: - View

struct WeeklyProgressCard: View {
    let progress: WeeklyProgressResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Динамика за неделю", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                if !progress.hasPrevious {
                    Text("первая неделя")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if progress.items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: progress.hasPrevious ? "checkmark.circle.fill" : "clock.fill")
                        .foregroundStyle(progress.hasPrevious ? Color.green : Color.secondary)
                    Text(progress.hasPrevious
                         ? "Нет активных рисков — всё в норме"
                         : "Недостаточно данных для сравнения")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(progress.items.indices, id: \.self) { index in
                    WeeklyProgressRow(item: progress.items[index])
                    if index < progress.items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WeeklyProgressRow: View {
    let item: WeeklyProgressItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.directionSymbol)
                .font(.title3)
                .foregroundStyle(item.directionColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(severitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.deltaText)
                    .font(.subheadline.bold())
                    .foregroundStyle(item.directionColor)
                Text(item.directionTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var severitySummary: String {
        if item.direction == "unchanged" {
            return "Уровень: \(item.currentSeverityLabel)"
        }
        return "Было: \(item.previousSeverityLabel) → Стало: \(item.currentSeverityLabel)"
    }

    private var accessibilityLabel: String {
        "\(item.label). \(item.directionTitle). \(severitySummary)"
    }
}

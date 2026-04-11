import SwiftUI

struct ReportDetailView: View {
    let report: AnalysisReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Период анализа")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(periodText)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                if report.risks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Отклонений не обнаружено")
                            .font(.headline)
                        Text("Все показатели в норме за данный период")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Выявленные риски")
                            .font(.headline)

                        ForEach(report.risks) { risk in
                            RiskDetailRow(risk: risk)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(formattedTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var formattedTitle: String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        guard let date = fmt.date(from: report.analyzedAt) else { return "Отчёт" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var periodText: String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        guard let from = fmt.date(from: report.periodFrom),
              let to = fmt.date(from: report.periodTo) else { return "" }
        return "\(from.formatted(date: .long, time: .shortened)) —\n\(to.formatted(date: .long, time: .shortened))"
    }
}

private struct RiskDetailRow: View {
    let risk: RiskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(severityColor)
                    .frame(width: 10, height: 10)
                Text(risk.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline.bold())
                Spacer()
                Text(severityLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(severityColor.opacity(0.15))
                    .foregroundStyle(severityColor)
                    .clipShape(Capsule())
            }
            Text(risk.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: risk.confidence)
                .tint(severityColor)
            Text("Уверенность: \(Int(risk.confidence * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var severityColor: Color {
        switch risk.severity {
        case "high": return .red
        case "moderate": return .orange
        default: return .yellow
        }
    }

    private var severityLabel: String {
        switch risk.severity {
        case "high": return "Высокий"
        case "moderate": return "Средний"
        default: return "Низкий"
        }
    }
}

import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading, viewModel.reports.isEmpty {
                    ProgressView("Загрузка...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.reports.isEmpty {
                    ContentUnavailableView(
                        "Нет данных",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("История отчётов появится после первой синхронизации")
                    )
                } else {
                    List {
                        ForEach(viewModel.reports) { report in
                            NavigationLink(destination: ReportDetailView(report: report)) {
                                ReportRow(report: report)
                            }
                        }

                        if viewModel.hasMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                                .onAppear { Task { await viewModel.loadMore() } }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("История")
            .task { await viewModel.loadInitial() }
            .refreshable { await viewModel.loadInitial() }
            .alert("Ошибка", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

private struct ReportRow: View {
    let report: AnalysisReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formattedDate(report.analyzedAt))
                    .font(.subheadline.bold())
                Spacer()
                if report.risks.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(topSeverityColor(report.risks))
                            .frame(width: 8, height: 8)
                        Text("\(report.risks.count) риск(а)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(periodText(report))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(date: .long, time: .omitted)
    }

    private func periodText(_ report: AnalysisReport) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        guard let rawFrom = report.periodFrom, let rawTo = report.periodTo,
              let from = fmt.date(from: rawFrom), let to = fmt.date(from: rawTo) else { return "" }
        return "\(from.formatted(date: .abbreviated, time: .shortened)) — \(to.formatted(date: .abbreviated, time: .shortened))"
    }

    private func topSeverityColor(_ risks: [RiskItem]) -> Color {
        if risks.contains(where: { $0.severity == "high" }) { return .red }
        if risks.contains(where: { $0.severity == "moderate" }) { return .orange }
        return .yellow
    }
}

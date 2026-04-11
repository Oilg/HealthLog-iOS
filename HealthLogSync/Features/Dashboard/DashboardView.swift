import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @ObservedObject private var syncManager = SyncManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SyncStatusCard(viewModel: viewModel)
                    if let report = viewModel.latestReport {
                        AnalysisReportCard(report: report)
                    } else if viewModel.isLoadingReport {
                        ProgressView("Загрузка отчёта...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if let error = viewModel.reportError {
                        ErrorCard(message: error)
                    }
                }
                .padding()
            }
            .navigationTitle("Сегодня")
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.refresh() }
        }
    }
}

private struct SyncStatusCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var syncManager = SyncManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Синхронизация", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                syncStatusBadge
            }

            if let lastSync = UserDefaultsManager.shared.lastSyncAt {
                Text("Последняя: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await syncManager.runDeltaSync() }
            } label: {
                Group {
                    if case .syncing = syncManager.state {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Синхронизация...")
                        }
                    } else {
                        Text("Синхронизировать сейчас")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: syncManager.state) { _, newState in
            if case .success = newState {
                Task { await viewModel.loadLatestReport() }
            }
        }
    }

    private var isSyncing: Bool {
        if case .syncing = syncManager.state { return true }
        return false
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        switch syncManager.state {
        case .idle:
            EmptyView()
        case .syncing:
            Text("В процессе")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        case .success(let count):
            Text("✓ \(count) записей")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        case .failure:
            Text("Ошибка")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        }
    }
}

private struct AnalysisReportCard: View {
    let report: AnalysisReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Анализ здоровья", systemImage: "waveform.path.ecg.rectangle")
                    .font(.headline)
                Spacer()
                Text(formattedDate(report.analyzedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if report.risks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Отклонений не обнаружено")
                        .font(.subheadline)
                }
            } else {
                ForEach(report.risks) { risk in
                    RiskRow(risk: risk)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct RiskRow: View {
    let risk: RiskItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(severityColor)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(risk.description)
                    .font(.subheadline)
                Text("Уверенность: \(Int(risk.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var severityColor: Color {
        switch risk.severity {
        case "high": return .red
        case "moderate": return .orange
        default: return .yellow
        }
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

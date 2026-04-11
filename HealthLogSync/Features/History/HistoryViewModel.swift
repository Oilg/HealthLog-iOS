import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var reports: [AnalysisReport] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = false
    @Published var showError = false
    @Published var errorMessage: String?

    private let pageSize = 20
    private var total = 0

    func loadInitial() async {
        isLoading = true
        reports = []
        total = 0
        await loadPage(offset: 0)
        isLoading = false
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await loadPage(offset: reports.count)
    }

    private func loadPage(offset: Int) async {
        do {
            let response = try await AnalysisService.shared.fetchHistory(limit: pageSize, offset: offset)
            if offset == 0 {
                reports = response.items
            } else {
                reports.append(contentsOf: response.items)
            }
            total = response.total
            hasMore = reports.count < total
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

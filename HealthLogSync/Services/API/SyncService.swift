import Foundation

final class SyncService {
    static let shared = SyncService()
    private init() {}

    func uploadRecords(from: Date, to: Date, records: [HealthRecord]) async throws -> SyncResponse {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let request = SyncRequest(
            syncFrom: formatter.string(from: from),
            syncTo: formatter.string(from: to),
            records: records
        )
        let response: SyncResponse = try await APIClient.shared.request(
            path: "/api/v1/sync",
            method: "POST",
            body: request
        )
        UserDefaultsManager.shared.lastSyncAt = to
        return response
    }

    func fetchStatus() async throws -> SyncStatusResponse {
        try await APIClient.shared.request(path: "/api/v1/sync/status")
    }
}

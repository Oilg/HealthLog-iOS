import Foundation

final class SyncService {
    static let shared = SyncService()
    private init() {}

    private var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    func uploadRecords(from: Date, to: Date, records: [HealthRecord]) async throws -> SyncResponse {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let request = SyncRequest(
            syncFrom: formatter.string(from: from),
            syncTo: formatter.string(from: to),
            records: records,
            appVersion: appVersion,
            platform: "iOS"
        )
        let response: SyncResponse = try await APIClient.shared.request(
            path: "/api/v1/sync",
            method: "POST",
            body: request
        )
        UserDefaultsManager.shared.lastSyncAt = to
        return response
    }

    func fetchSyncStatus() async throws -> SyncStatusResponse {
        // postSessionExpiredOnUnauthorized: false — this is a best-effort check on login;
        // a 401 here must not trigger logout (tokens may not yet be propagated server-side).
        try await APIClient.shared.request(
            path: "/api/v1/health/sync/status",
            method: "GET",
            body: nil as String?,
            postSessionExpiredOnUnauthorized: false
        )
    }
}

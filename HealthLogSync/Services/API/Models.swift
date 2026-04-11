import Foundation

struct AuthRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
}

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct SyncRequest: Encodable {
    let syncFrom: String
    let syncTo: String
    let records: [HealthRecord]

    enum CodingKeys: String, CodingKey {
        case syncFrom = "sync_from"
        case syncTo = "sync_to"
        case records
    }
}

struct HealthRecord: Encodable {
    let type: String
    let sourceName: String
    let sourceVersion: String?
    let creationDate: String
    let startDate: String
    let endDate: String
    let value: String
    let unit: String
    let metadata: [String: String]
    let instantaneousBpm: [InstantaneousBPM]?

    enum CodingKeys: String, CodingKey {
        case type, value, unit, metadata
        case sourceName = "sourceName"
        case sourceVersion = "sourceVersion"
        case creationDate = "creationDate"
        case startDate = "startDate"
        case endDate = "endDate"
        case instantaneousBpm = "instantaneous_bpm"
    }
}

struct InstantaneousBPM: Encodable {
    let bpm: Int
    let time: String
}

struct SyncResponse: Decodable {
    let syncId: String
    let syncedRecords: Int
    let nextSyncFrom: String

    enum CodingKeys: String, CodingKey {
        case syncId = "sync_id"
        case syncedRecords = "synced_records"
        case nextSyncFrom = "next_sync_from"
    }
}

struct SyncStatusResponse: Decodable {
    let lastSyncAt: String?
    let lastSyncRecords: Int?

    enum CodingKeys: String, CodingKey {
        case lastSyncAt = "last_sync_at"
        case lastSyncRecords = "last_sync_records"
    }
}

struct AnalysisReport: Decodable, Identifiable {
    let id: String
    let analyzedAt: String
    let periodFrom: String
    let periodTo: String
    let risks: [RiskItem]

    enum CodingKeys: String, CodingKey {
        case id
        case analyzedAt = "analyzed_at"
        case periodFrom = "period_from"
        case periodTo = "period_to"
        case risks
    }
}

struct RiskItem: Decodable, Identifiable {
    var id: String { type }
    let type: String
    let severity: String
    let confidence: Double
    let description: String
}

struct AnalysisHistoryResponse: Decodable {
    let items: [AnalysisReport]
    let total: Int
}

struct APIError: Decodable, Error {
    let detail: String
}

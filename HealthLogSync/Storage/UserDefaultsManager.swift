import Foundation

enum UserDefaultsKey: String {
    case lastSyncAt
    case initialSyncCompleted
    case initialSyncProgress
    case userId
    case userEmail
    case healthKitAuthorized
}

final class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    private let defaults = UserDefaults.standard
    private init() {}

    var lastSyncAt: Date? {
        get { defaults.object(forKey: UserDefaultsKey.lastSyncAt.rawValue) as? Date }
        set { defaults.set(newValue, forKey: UserDefaultsKey.lastSyncAt.rawValue) }
    }

    var initialSyncCompleted: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.initialSyncCompleted.rawValue) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.initialSyncCompleted.rawValue) }
    }

    var initialSyncProgress: Date? {
        get { defaults.object(forKey: UserDefaultsKey.initialSyncProgress.rawValue) as? Date }
        set { defaults.set(newValue, forKey: UserDefaultsKey.initialSyncProgress.rawValue) }
    }

    var userId: String? {
        get { defaults.string(forKey: UserDefaultsKey.userId.rawValue) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.userId.rawValue) }
    }

    var userEmail: String? {
        get { defaults.string(forKey: UserDefaultsKey.userEmail.rawValue) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.userEmail.rawValue) }
    }

    var healthKitAuthorized: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.healthKitAuthorized.rawValue) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.healthKitAuthorized.rawValue) }
    }

    // MARK: - DOB sync flag (per-user, keyed by email)

    /// Returns the UserDefaults key for the DOB-synced flag scoped to the current user.
    /// Falls back to a generic key when no email is stored yet so the flag is always
    /// reachable — `clearUserData()` removes both the scoped and the fallback key.
    private func dobSyncedKey(for email: String? = nil) -> String {
        let identifier = email ?? userEmail ?? "_anonymous"
        return "dateOfBirthSyncedToBackend_\(identifier)"
    }

    var dateOfBirthSynced: Bool {
        get { defaults.bool(forKey: dobSyncedKey()) }
        set { defaults.set(newValue, forKey: dobSyncedKey()) }
    }

    func clearUserData() {
        // Remove DOB flag synchronously before clearing the email so the key is still resolvable.
        defaults.removeObject(forKey: dobSyncedKey())
        userId = nil
        userEmail = nil
        lastSyncAt = nil
        initialSyncCompleted = false
        initialSyncProgress = nil
    }
}

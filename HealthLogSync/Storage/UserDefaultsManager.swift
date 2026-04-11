import Foundation

enum UserDefaultsKey: String {
    case lastSyncAt = "lastSyncAt"
    case initialSyncCompleted = "initialSyncCompleted"
    case initialSyncProgress = "initialSyncProgress"
    case userId = "userId"
    case userEmail = "userEmail"
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

    func clearUserData() {
        userId = nil
        userEmail = nil
        lastSyncAt = nil
        initialSyncCompleted = false
        initialSyncProgress = nil
    }
}

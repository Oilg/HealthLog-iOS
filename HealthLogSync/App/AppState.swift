import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool
    @Published var isHealthKitAuthorized: Bool
    @Published var initialSyncCompleted: Bool

    private var sessionExpiredObserver: NSObjectProtocol?

    init() {
        isLoggedIn = AuthService.shared.isLoggedIn
        initialSyncCompleted = UserDefaultsManager.shared.initialSyncCompleted
        isHealthKitAuthorized = UserDefaultsManager.shared.healthKitAuthorized
        observeSessionExpiry()
    }

    deinit {
        if let observer = sessionExpiredObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observeSessionExpiry() {
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: .sessionDidExpire,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSessionExpiry()
            }
        }
    }

    private func handleSessionExpiry() {
        AuthService.shared.clearSession()
        isLoggedIn = false
        initialSyncCompleted = false
    }

    func onLoginSuccess() {
        isLoggedIn = true
    }

    func onLogout() {
        Task { try? await AuthService.shared.logout() }
        isLoggedIn = false
        initialSyncCompleted = false
    }

    func onInitialSyncCompleted() {
        initialSyncCompleted = true
    }
}

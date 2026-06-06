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
        Task {
            await checkSyncStatusAndSkipOnboardingIfNeeded()
        }
    }

    private func checkSyncStatusAndSkipOnboardingIfNeeded() async {
        do {
            let status = try await SyncService.shared.fetchSyncStatus()
            if status.hasData {
                if let lastSyncString = status.lastSyncAt {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: lastSyncString) {
                        UserDefaultsManager.shared.lastSyncAt = date
                    }
                }
                UserDefaultsManager.shared.initialSyncCompleted = true
                initialSyncCompleted = true
            }
        } catch {
            // Network error or endpoint unavailable — fall through to normal onboarding
        }
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

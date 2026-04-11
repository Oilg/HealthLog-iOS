import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool
    @Published var isHealthKitAuthorized = false
    @Published var initialSyncCompleted: Bool

    init() {
        isLoggedIn = AuthService.shared.isLoggedIn
        initialSyncCompleted = UserDefaultsManager.shared.initialSyncCompleted
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

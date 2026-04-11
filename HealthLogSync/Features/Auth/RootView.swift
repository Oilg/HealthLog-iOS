import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.isLoggedIn {
                AuthView()
            } else if !appState.isHealthKitAuthorized {
                HealthKitPermissionView()
            } else if !appState.initialSyncCompleted {
                InitialSyncView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut, value: appState.isLoggedIn)
    }
}

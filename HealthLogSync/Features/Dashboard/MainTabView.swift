import SwiftUI

struct MainTabView: View {
    /// Tab indices match the order tabs appear below.
    private enum Tab: Int {
        case dashboard = 0
        case history = 1
        case settings = 2
    }

    @State private var selectedTab: Int = Tab.dashboard.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Сегодня", systemImage: "heart.text.square")
                }
                .tag(Tab.dashboard.rawValue)

            HistoryView()
                .tabItem {
                    Label("История", systemImage: "calendar")
                }
                .tag(Tab.history.rawValue)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
                .tag(Tab.settings.rawValue)
        }
        .onAppear {
            // Handle cold-start case: push arrived before MainTabView was alive and
            // subscribed to NotificationCenter. AppDelegate stored the action in
            // pendingAction; consume it here.
            if AppDelegate.pendingAction == "open_profile" {
                AppDelegate.pendingAction = nil
                navigateToProfile()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProfile)) { _ in
            // Push payload with action=open_profile asked us to navigate to the
            // profile/settings screen so the user can fill in DOB.
            AppDelegate.pendingAction = nil
            navigateToProfile()
        }
    }

    private func navigateToProfile() {
        selectedTab = Tab.settings.rawValue
        AppDelegate.pendingHighlightDOB = true
    }
}

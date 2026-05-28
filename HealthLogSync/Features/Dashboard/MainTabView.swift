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
        .onReceive(NotificationCenter.default.publisher(for: .openProfile)) { _ in
            // Push payload with action=open_profile asked us to navigate to the
            // profile/settings screen so the user can fill in DOB.
            selectedTab = Tab.settings.rawValue
        }
    }
}

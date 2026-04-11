import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Сегодня", systemImage: "heart.text.square")
                }

            HistoryView()
                .tabItem {
                    Label("История", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Аккаунт") {
                    if let email = UserDefaultsManager.shared.userEmail {
                        LabeledContent("Email", value: email)
                    }
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("Синхронизация") {
                    if let lastSync = UserDefaultsManager.shared.lastSyncAt {
                        LabeledContent("Последняя синхронизация") {
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Расписание") {
                        Text("Ежедневно в ~10:00")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("О приложении") {
                    LabeledContent("Версия") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Настройки")
            .confirmationDialog("Выйти из аккаунта?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) {
                    appState.onLogout()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Данные синхронизации останутся на сервере")
            }
        }
    }
}

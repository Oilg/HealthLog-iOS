import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogoutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

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
                    Link(destination: URL(string: "http://5.129.199.50/privacy")!) {
                        Label("Политика конфиденциальности", systemImage: "doc.text")
                    }
                }

                Section {
                    if let error = deleteError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        if isDeletingAccount {
                            HStack {
                                ProgressView().tint(.red)
                                Text("Удаление…")
                            }
                        } else {
                            Label("Удалить аккаунт", systemImage: "trash")
                        }
                    }
                    .disabled(isDeletingAccount)
                } footer: {
                    Text("Аккаунт и все данные здоровья будут безвозвратно удалены с сервера.")
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
            .confirmationDialog(
                "Удалить аккаунт?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Удалить безвозвратно", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Все ваши данные здоровья и история анализов будут удалены. Это действие нельзя отменить.")
            }
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        deleteError = nil
        do {
            try await AuthService.shared.deleteAccount()
            appState.onLogout()
        } catch {
            deleteError = "Не удалось удалить аккаунт. Попробуйте ещё раз."
            isDeletingAccount = false
        }
    }
}

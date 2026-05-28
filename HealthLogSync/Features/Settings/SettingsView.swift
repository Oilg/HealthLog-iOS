import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogoutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    @State private var dateOfBirth: Date?
    /// `true` once the user has explicitly set a DOB or the server returned one.
    /// While `false` we show a button instead of DatePicker to avoid the fake default date.
    @State private var isDateSet: Bool = false
    @State private var isLoadingProfile = false
    @State private var dobErrorMessage: String?
    @State private var pendingDOBSave: Task<Void, Never>?
    @State private var showDOBHighlightBanner = false

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dobRange(now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date> {
        let lower = calendar.date(byAdding: .year, value: -130, to: now) ?? now
        let upper = calendar.date(byAdding: .year, value: -5, to: now) ?? now
        return lower ... upper
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Аккаунт") {
                    if let email = UserDefaultsManager.shared.userEmail {
                        LabeledContent("Email", value: email)
                    }

                    profileSection

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
        .task {
            await loadProfile()
            if AppDelegate.pendingHighlightDOB {
                AppDelegate.pendingHighlightDOB = false
                showDOBHighlightBanner = true
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showDOBHighlightBanner = false
            }
        }
        .onDisappear { pendingDOBSave?.cancel() }
        .overlay(alignment: .top) {
            if showDOBHighlightBanner {
                Text("Заполните дату рождения для точного анализа активности")
                    .font(.footnote)
                    .padding(10)
                    .background(Color(.systemYellow).opacity(0.9))
                    .cornerRadius(8)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut, value: showDOBHighlightBanner)
            }
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if isLoadingProfile {
            HStack {
                Text("Дата рождения")
                Spacer()
                ProgressView()
            }
        } else if isDateSet {
            DatePicker(
                "Дата рождения",
                selection: Binding(
                    get: { dateOfBirth ?? defaultDOB() },
                    set: { newValue in
                        isDateSet = true
                        dateOfBirth = newValue
                        scheduleDOBSave(newValue)
                    }
                ),
                in: Self.dobRange(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .accessibilityHint("Сохраняется автоматически после изменения")

            if let error = dobErrorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Ошибка: \(error)")
            }
        } else {
            Button {
                isDateSet = true
                dateOfBirth = defaultDOB()
            } label: {
                Text("Указать дату рождения")
            }

            if let error = dobErrorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Ошибка: \(error)")
            }
        }
    }

    private func defaultDOB() -> Date {
        // Default to 30 years ago so the picker opens on a sensible value
        // when the user has not set a DOB yet.
        Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    }

    private func loadProfile() async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            let profile = try await AuthService.shared.fetchProfile()
            if let dob = profile.dateOfBirth, let parsed = Self.isoDateFormatter.date(from: dob) {
                dateOfBirth = parsed
                isDateSet = true
            } else {
                isDateSet = false
            }
        } catch {
            dobErrorMessage = "Не удалось загрузить профиль"
        }
    }

    private func scheduleDOBSave(_ newValue: Date) {
        // Debounce: DatePicker emits set() on every spin; we only want to PATCH
        // once the user settles on a value. 600ms is short enough to feel instant
        // but long enough to coalesce normal scroll-through interactions.
        pendingDOBSave?.cancel()
        pendingDOBSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await saveDOB(newValue)
        }
    }

    private func saveDOB(_ date: Date) async {
        let iso = Self.isoDateFormatter.string(from: date)
        dobErrorMessage = nil
        do {
            _ = try await AuthService.shared.updateProfile(
                timezone: TimeZone.current.identifier,
                dateOfBirth: iso
            )
        } catch {
            dobErrorMessage = "Не удалось сохранить дату рождения"
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

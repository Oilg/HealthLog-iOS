import SwiftUI

struct AuthView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = AuthViewModel()
    /// Set to true once onLoginSuccess has been called to avoid double-invocation.
    @State private var didFinishLogin = false
    /// Prevents re-triggering biometric auth every time the view re-appears (e.g. from background).
    @State private var didAttemptBiometricOnAppear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.red)
                        Text("HealthLog")
                            .font(.largeTitle.bold())
                        Text("Анализ данных здоровья")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 40)

                    VStack(spacing: 16) {
                        if viewModel.isRegistering {
                            registrationFields
                        }

                        TextField("Email", text: $viewModel.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)

                        passwordField

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task {
                                let success = await viewModel.submit()
                                // For login, onLoginSuccess is triggered by the
                                // save-credentials alert (either button). For
                                // registration there is no alert, so call directly.
                                if success, viewModel.isRegistering {
                                    appState.onLoginSuccess()
                                }
                            }
                        } label: {
                            Group {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(viewModel.isRegistering ? "Создать аккаунт" : "Войти")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isSubmitDisabled)

                        if !viewModel.isRegistering, viewModel.isBiometricAvailable {
                            biometricButton
                        }
                    }
                    .padding(.horizontal, 32)

                    Button {
                        viewModel.toggleMode()
                    } label: {
                        Text(viewModel.isRegistering ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Создать")
                            .font(.footnote)
                            .foregroundStyle(.blue)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            guard !didAttemptBiometricOnAppear, viewModel.isBiometricAvailable else { return }
            didAttemptBiometricOnAppear = true
            Task {
                let success = await viewModel.loginWithBiometrics()
                if success { finishLogin() }
            }
        }
        .alert("Сохранить для Face ID?", isPresented: $viewModel.showSaveCredentialsAlert) {
            Button("Сохранить") {
                viewModel.saveCredentialsForBiometrics()
                finishLogin()
            }
            Button("Не сейчас", role: .cancel) {
                finishLogin()
            }
        } message: {
            Text("Хотите входить в приложение быстрее с помощью биометрии?")
        }
        // Guard against system-dismiss (e.g. programmatic binding reset) leaving the
        // user stuck on the login screen with a valid session.
        .onChange(of: viewModel.showSaveCredentialsAlert) { isShowing in
            if !isShowing { finishLogin() }
        }
    }

    private func finishLogin() {
        guard !didFinishLogin else { return }
        didFinishLogin = true
        appState.onLoginSuccess()
    }

    // MARK: - Subviews

    private var biometricButton: some View {
        Button {
            Task {
                let success = await viewModel.loginWithBiometrics()
                if success { appState.onLoginSuccess() }
            }
        } label: {
            Label(viewModel.biometricButtonLabel, systemImage: viewModel.biometricSystemImage)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isLoading)
    }

    private var passwordField: some View {
        HStack(spacing: 8) {
            Group {
                if viewModel.isPasswordVisible {
                    TextField("Пароль", text: $viewModel.password)
                } else {
                    SecureField("Пароль", text: $viewModel.password)
                }
            }
            .textContentType(viewModel.isRegistering ? .newPassword : .password)
            .autocapitalization(.none)
            .disableAutocorrection(true)

            Button {
                viewModel.togglePasswordVisibility()
            } label: {
                Image(systemName: viewModel.isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPasswordVisible ? "Скрыть пароль" : "Показать пароль")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(uiColor: .systemGray4), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var registrationFields: some View {
        TextField("Имя", text: $viewModel.firstName)
            .textContentType(.givenName)
            .textFieldStyle(.roundedBorder)

        TextField("Фамилия", text: $viewModel.lastName)
            .textContentType(.familyName)
            .textFieldStyle(.roundedBorder)

        TextField("Телефон", text: $viewModel.phone)
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
            .textFieldStyle(.roundedBorder)

        Picker("Пол", selection: $viewModel.sex) {
            Text("Мужской").tag("male")
            Text("Женский").tag("female")
        }
        .pickerStyle(.segmented)
    }
}

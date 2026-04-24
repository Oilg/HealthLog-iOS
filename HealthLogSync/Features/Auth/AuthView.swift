import SwiftUI

struct AuthView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = AuthViewModel()

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

                        SecureField("Пароль", text: $viewModel.password)
                            .textContentType(viewModel.isRegistering ? .newPassword : .password)
                            .textFieldStyle(.roundedBorder)

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task {
                                let success = await viewModel.submit()
                                if success { appState.onLoginSuccess() }
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

import SwiftUI

struct HealthKitPermissionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRequesting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)

            VStack(spacing: 12) {
                Text("Доступ к данным здоровья")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Приложению нужен доступ к Apple Health для автоматической синхронизации и анализа данных о вашем здоровье.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(icon: "heart.fill", text: "Пульс и вариабельность ритма")
                PermissionRow(icon: "bed.double.fill", text: "Анализ сна")
                PermissionRow(icon: "lungs.fill", text: "SpO2 и частота дыхания")
                PermissionRow(icon: "figure.walk", text: "Активность и шаги")
                PermissionRow(icon: "waveform.path.ecg", text: "ЭКГ и другие показатели")
            }
            .padding(.horizontal, 32)

            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await requestPermission() }
            } label: {
                Group {
                    if isRequesting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Разрешить доступ")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func requestPermission() async {
        isRequesting = true
        errorMessage = nil
        do {
            try await HealthKitManager.shared.requestAuthorization()
            UserDefaultsManager.shared.healthKitAuthorized = true
            appState.isHealthKitAuthorized = true

            // Background delivery + observers can only be enabled for
            // authorized types. AppDelegate's launch-time call no-ops for a
            // new user who hasn't accepted the HealthKit prompt yet — kick
            // off the installation now that we have authorization, otherwise
            // background sync wouldn't start until the next app launch.
            HealthKitManager.shared.enableBackgroundDeliveryAndStartObservers {
                Task { @MainActor in
                    SyncManager.shared.resetState()
                    await SyncManager.shared.runDeltaSync()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isRequesting = false
    }
}

private struct PermissionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.red)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

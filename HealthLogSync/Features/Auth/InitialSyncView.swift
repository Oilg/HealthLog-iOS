import SwiftUI

struct InitialSyncView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var syncManager = SyncManager.shared

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "icloud.and.arrow.up.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Загрузка данных")
                    .font(.title2.bold())

                if syncManager.isInitialSyncRunning {
                    Text("Загружаем: \(syncManager.initialSyncProgress)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ProgressView()
                        .padding(.top, 8)
                } else {
                    Text("Выполним первоначальную загрузку всей истории из Apple Health. Это займёт несколько минут.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            if !syncManager.isInitialSyncRunning {
                Button {
                    Task {
                        await syncManager.runInitialSync()
                        appState.onInitialSyncCompleted()
                    }
                } label: {
                    Text("Начать загрузку")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)

                Button {
                    UserDefaultsManager.shared.initialSyncCompleted = true
                    appState.onInitialSyncCompleted()
                } label: {
                    Text("Пропустить")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .onChange(of: syncManager.isInitialSyncRunning) { _, running in
            if !running && UserDefaultsManager.shared.initialSyncCompleted {
                appState.onInitialSyncCompleted()
            }
        }
    }
}

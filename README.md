# HealthLog iOS

iOS-приложение для автоматической синхронизации данных Apple Health с сервером HealthLog.

## Требования

- Xcode 15+
- iOS 17+
- Реальное устройство (HealthKit не работает в симуляторе)
- Apple Developer Program ($99/год)

## Настройка перед сборкой

### 1. Bundle ID и Signing

1. Открыть `HealthLogSync.xcodeproj` в Xcode
2. Выбрать таргет `HealthLogSync` → вкладка **Signing & Capabilities**
3. Выбрать свой **Team**
4. В поле **Bundle Identifier** вписать тот же ID что создан в Apple Developer Portal (например `com.yourname.healthlogsync`)

### 2. Адрес сервера

Если сервер переехал на домен — обновить `baseURL` в `APIClient.swift`:

```swift
private let baseURL: String = "http://5.129.199.50"
```

### 3. Bundle ID в Info.plist и entitlements

Убедиться что `PRODUCT_BUNDLE_IDENTIFIER` в Build Settings совпадает с App ID в Apple Developer Portal.

## Архитектура

```
HealthLogSync/
├── App/                        # Entry point, AppDelegate, AppState
├── Features/
│   ├── Auth/                   # Вход, регистрация, разрешения HealthKit, начальная синхронизация
│   ├── Dashboard/              # Главный экран: последний отчёт + статус синхронизации
│   ├── History/                # История отчётов
│   └── Settings/               # Настройки, выход
├── Services/
│   ├── API/                    # APIClient, AuthService, SyncService, AnalysisService
│   ├── HealthKit/              # HealthKitManager, HealthKitTypes
│   └── Sync/                   # SyncManager (оркестрация)
├── Background/                 # BGTaskScheduler — фоновая синхронизация
└── Storage/                    # KeychainManager, UserDefaultsManager
```

## Поток данных

1. При входе запрашиваются разрешения HealthKit
2. Первая синхронизация: все данные с момента появления первой записи, порциями по месяцу
3. Ежедневная фоновая синхронизация: данные с момента последней синхронизации
4. Результаты анализа отображаются на главном экране и в истории

## Backend API

Приложение работает с эндпоинтами:

| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/api/v1/auth/login` | Вход |
| POST | `/api/v1/auth/register` | Регистрация |
| POST | `/api/v1/auth/refresh` | Обновление токенов |
| POST | `/api/v1/sync` | Загрузка данных здоровья (JSON) |
| GET | `/api/v1/sync/status` | Статус синхронизации |
| GET | `/api/v1/analysis/latest` | Последний отчёт |
| GET | `/api/v1/analysis/history` | История отчётов |

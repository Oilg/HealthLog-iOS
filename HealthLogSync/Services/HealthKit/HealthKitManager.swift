import Foundation
import HealthKit
import os

final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()
    private let log = Logger(subsystem: "com.healthlogsync", category: "HealthKit")
    private let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    /// Active observer queries kept alive for the lifetime of the app.
    /// HKObserverQuery must be retained by us or HealthKit silently drops it.
    private var activeObservers: [HKObserverQuery] = []

    /// Serial queue protecting `pendingObserverWorkItem` from being mutated
    /// concurrently by callbacks from multiple HKObserverQuery instances
    /// firing on different background queues.
    private let observerDebounceQueue = DispatchQueue(label: "com.healthlogsync.healthkit.observer")
    private var pendingObserverWorkItem: DispatchWorkItem?

    /// Debounce window for HKObserverQuery callbacks. iOS may fire observers
    /// up to ~12 times per minute in the foreground — without debouncing this
    /// would saturate the backend's 200 req/hour rate limit in ~17 minutes.
    /// 60 seconds collapses a burst of notifications into a single sync.
    static let observerDebounceInterval: TimeInterval = 60

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: HealthKitTypes.allReadTypes)
    }

    func fetchRecords(from startDate: Date, to endDate: Date) async -> [HealthRecord] {
        var records: [HealthRecord] = []
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        for descriptor in HealthKitTypes.quantityTypes {
            guard let type = HKQuantityType.quantityType(forIdentifier: descriptor.identifier) else { continue }
            let samples = await fetchQuantitySamples(type: type, unit: descriptor.unit, predicate: predicate)
            records.append(contentsOf: samples)
        }

        for identifier in HealthKitTypes.categoryTypeIdentifiers {
            guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { continue }
            let samples = await fetchCategorySamples(type: type, predicate: predicate)
            records.append(contentsOf: samples)
        }

        return records
    }

    func earliestDataDate() async -> Date? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [
                NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true),
            ]) { [log] _, samples, error in
                if let error {
                    log.error("earliestDataDate HKSampleQuery error: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.startDate)
            }
            store.execute(query)
        }
    }

    private func fetchQuantitySamples(
        type: HKQuantityType,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> [HealthRecord] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { [weak self] _, samples, error in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                if let error {
                    // Common case: errorHealthDataUnavailable when device is locked
                    // (file-protection prevents HealthKit reads). Previously this was
                    // silently ignored — now we log and continue returning empty.
                    log.error(
                        "fetchQuantitySamples \(type.identifier, privacy: .public) error: \(error.localizedDescription, privacy: .public)"
                    )
                }
                let records = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthRecord(
                        type: sample.quantityType.identifier,
                        sourceName: sample.sourceRevision.source.name,
                        sourceVersion: sample.sourceRevision.version,
                        creationDate: self.isoFormatter.string(from: sample.startDate),
                        startDate: self.isoFormatter.string(from: sample.startDate),
                        endDate: self.isoFormatter.string(from: sample.endDate),
                        value: String(format: "%.6g", sample.quantity.doubleValue(for: unit)),
                        unit: unit.unitString,
                        metadata: [:],
                        instantaneousBpm: nil
                    )
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }

    private func fetchCategorySamples(
        type: HKCategoryType,
        predicate: NSPredicate
    ) async -> [HealthRecord] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { [weak self] _, samples, error in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
                if let error {
                    log.error(
                        "fetchCategorySamples \(type.identifier, privacy: .public) error: \(error.localizedDescription, privacy: .public)"
                    )
                }
                let records = (samples as? [HKCategorySample] ?? []).map { sample in
                    HealthRecord(
                        type: sample.categoryType.identifier,
                        sourceName: sample.sourceRevision.source.name,
                        sourceVersion: sample.sourceRevision.version,
                        creationDate: self.isoFormatter.string(from: sample.startDate),
                        startDate: self.isoFormatter.string(from: sample.startDate),
                        endDate: self.isoFormatter.string(from: sample.endDate),
                        value: String(sample.value),
                        unit: "",
                        metadata: [:],
                        instantaneousBpm: nil
                    )
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }

    // MARK: - Background delivery

    /// Types we want HealthKit to wake us up for in the background.
    /// We pick high-frequency signals coming from the watch: a new heart-rate
    /// sample is a reliable proxy for "watch synced fresh data to the iPhone".
    private static let backgroundDeliveryQuantityTypes: [(HKQuantityTypeIdentifier, HKUpdateFrequency)] = [
        (.heartRate, .immediate),
        (.stepCount, .hourly),
    ]

    private static let backgroundDeliveryCategoryTypes: [(HKCategoryTypeIdentifier, HKUpdateFrequency)] = [
        (.sleepAnalysis, .immediate),
    ]

    /// Enables background delivery and installs an HKObserverQuery for every
    /// background-delivery type whose authorization has been granted.
    ///
    /// `authorizationStatus(for:)` reflects *write* (sharing) authorization and
    /// always returns `.notDetermined` for read-only types (heartRate, stepCount,
    /// sleepAnalysis) because we request `toShare: []`. Using it as a read-auth
    /// guard caused `enableBackgroundDelivery` and `installObserver` to be
    /// skipped unconditionally. We now use `UserDefaultsManager.healthKitAuthorized`
    /// as the proxy — it is set to `true` by `HealthKitPermissionView` immediately
    /// after a successful `requestAuthorization` call.
    ///
    /// One HKObserverQuery is installed per enabled type because HealthKit
    /// requires a live observer to actually deliver background updates;
    /// `enableBackgroundDelivery` on a type without an observer is a no-op.
    /// Safe to call multiple times — observers are tracked and not duplicated.
    ///
    /// `onSampleAvailable` is invoked on `observerDebounceQueue` after the
    /// debounce window (see `observerDebounceInterval`) so a burst of
    /// observer fires triggers exactly one downstream sync. Callers must
    /// hop onto the main actor themselves if they touch main-actor state.
    func enableBackgroundDeliveryAndStartObservers(onSampleAvailable: @escaping @Sendable () -> Void) {
        guard isAvailable else { return }
        // The `UserDefaultsManager.healthKitAuthorized` flag is set only through
        // `HealthKitPermissionView`. After a reinstall, UserDefaults wipe, or
        // authorization change through iOS Settings the flag may be stale-false
        // while HealthKit access is still valid. `enableBackgroundDelivery` for an
        // unauthorized type returns an error in its callback (logged, not fatal),
        // so it is safe to attempt unconditionally when the device supports HealthKit.

        for (identifier, frequency) in Self.backgroundDeliveryQuantityTypes {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            enableBackgroundDelivery(for: type, identifier: identifier.rawValue, frequency: frequency)
            installObserver(for: type, identifier: identifier.rawValue, onSampleAvailable: onSampleAvailable)
        }

        for (identifier, frequency) in Self.backgroundDeliveryCategoryTypes {
            guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { continue }
            enableBackgroundDelivery(for: type, identifier: identifier.rawValue, frequency: frequency)
            installObserver(for: type, identifier: identifier.rawValue, onSampleAvailable: onSampleAvailable)
        }
    }

    private func enableBackgroundDelivery(for type: HKSampleType, identifier: String, frequency: HKUpdateFrequency) {
        store.enableBackgroundDelivery(for: type, frequency: frequency) { [log] success, error in
            if let error {
                log.error(
                    "enableBackgroundDelivery \(identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            } else {
                log.info(
                    "enableBackgroundDelivery \(identifier, privacy: .public) success=\(success, privacy: .public)"
                )
            }
        }
    }

    private func installObserver(
        for type: HKSampleType,
        identifier: String,
        onSampleAvailable: @escaping @Sendable () -> Void
    ) {
        // Avoid stacking duplicate observers on subsequent calls.
        if activeObservers.contains(where: { $0.objectType?.identifier == type.identifier }) {
            return
        }
        let observer = HKObserverQuery(sampleType: type, predicate: nil) { [weak self, log] _, completionHandler, error in
            if let error {
                log.error(
                    "observer \(identifier, privacy: .public) fired with error: \(error.localizedDescription, privacy: .public)"
                )
            } else {
                log.info("observer \(identifier, privacy: .public) fired — new samples available")
                self?.scheduleDebouncedNotification(onSampleAvailable)
            }
            // Must always call completion or HealthKit stops delivering updates.
            completionHandler()
        }
        store.execute(observer)
        activeObservers.append(observer)
    }

    /// Coalesces a burst of HKObserverQuery callbacks into a single delayed
    /// invocation of `callback`. Any new fire within the debounce window
    /// resets the timer; the user-visible effect is "after observers stop
    /// firing for `observerDebounceInterval` seconds, sync once".
    ///
    /// Internal so unit tests can exercise the coalescing contract without
    /// going through HealthKit.
    func scheduleDebouncedNotification(_ callback: @escaping @Sendable () -> Void) {
        observerDebounceQueue.async { [weak self] in
            guard let self else { return }
            pendingObserverWorkItem?.cancel()
            let workItem = DispatchWorkItem { callback() }
            pendingObserverWorkItem = workItem
            observerDebounceQueue.asyncAfter(
                deadline: .now() + Self.observerDebounceInterval,
                execute: workItem
            )
        }
    }
}

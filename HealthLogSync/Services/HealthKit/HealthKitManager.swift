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

    /// Enables background delivery and installs an HKObserverQuery for heart-rate.
    /// Safe to call multiple times — observer queries are tracked and not duplicated
    /// after the first successful install (we re-execute on subsequent calls in case
    /// the app was relaunched and HealthKit dropped the prior query).
    ///
    /// `onSampleAvailable` is invoked on an arbitrary background queue whenever
    /// HealthKit signals that new data has arrived. The caller is expected to
    /// hop to the main actor and trigger a sync.
    func enableBackgroundDeliveryAndStartObservers(onSampleAvailable: @escaping () -> Void) {
        guard isAvailable else { return }

        for (identifier, frequency) in Self.backgroundDeliveryQuantityTypes {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            store.enableBackgroundDelivery(for: type, frequency: frequency) { [log] success, error in
                if let error {
                    log.error(
                        "enableBackgroundDelivery \(identifier.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    log.info(
                        "enableBackgroundDelivery \(identifier.rawValue, privacy: .public) success=\(success, privacy: .public)"
                    )
                }
            }
        }

        for (identifier, frequency) in Self.backgroundDeliveryCategoryTypes {
            guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { continue }
            store.enableBackgroundDelivery(for: type, frequency: frequency) { [log] success, error in
                if let error {
                    log.error(
                        "enableBackgroundDelivery \(identifier.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    log.info(
                        "enableBackgroundDelivery \(identifier.rawValue, privacy: .public) success=\(success, privacy: .public)"
                    )
                }
            }
        }

        // Install observer query for heart-rate as the primary "new data" signal.
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate), activeObservers.isEmpty {
            let observer = HKObserverQuery(sampleType: heartRate, predicate: nil) { [log] _, completionHandler, error in
                if let error {
                    log.error("heartRate observer fired with error: \(error.localizedDescription, privacy: .public)")
                } else {
                    log.info("heartRate observer fired — new samples available")
                    onSampleAvailable()
                }
                // Must always call completion or HealthKit stops delivering updates.
                completionHandler()
            }
            store.execute(observer)
            activeObservers.append(observer)
        }
    }
}

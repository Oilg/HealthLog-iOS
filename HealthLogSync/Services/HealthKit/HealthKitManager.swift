import HealthKit
import Foundation

final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

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
                NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            ]) { _, samples, _ in
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
            ) { [weak self] _, samples, _ in
                guard let self else {
                    continuation.resume(returning: [])
                    return
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
            ) { [weak self] _, samples, _ in
                guard let self else {
                    continuation.resume(returning: [])
                    return
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
}

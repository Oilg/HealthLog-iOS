import HealthKit

struct HKTypeDescriptor {
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
}

enum HealthKitTypes {
    static let quantityTypes: [HKTypeDescriptor] = [
        HKTypeDescriptor(identifier: .heartRate, unit: HKUnit(from: "count/min")),
        HKTypeDescriptor(identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)),
        HKTypeDescriptor(identifier: .oxygenSaturation, unit: .percent()),
        HKTypeDescriptor(identifier: .respiratoryRate, unit: HKUnit(from: "count/min")),
        HKTypeDescriptor(identifier: .bodyTemperature, unit: .degreeCelsius()),
        HKTypeDescriptor(identifier: .bloodPressureSystolic, unit: .millimeterOfMercury()),
        HKTypeDescriptor(identifier: .bloodPressureDiastolic, unit: .millimeterOfMercury()),
        HKTypeDescriptor(identifier: .vo2Max, unit: HKUnit(from: "ml/kg*min")),
        HKTypeDescriptor(identifier: .stepCount, unit: .count()),
        HKTypeDescriptor(identifier: .distanceWalkingRunning, unit: .meter()),
        HKTypeDescriptor(identifier: .activeEnergyBurned, unit: .kilocalorie()),
        HKTypeDescriptor(identifier: .basalEnergyBurned, unit: .kilocalorie()),
        HKTypeDescriptor(identifier: .appleExerciseTime, unit: .minute()),
        HKTypeDescriptor(identifier: .bodyMass, unit: .gramUnit(with: .kilo)),
        HKTypeDescriptor(identifier: .bodyMassIndex, unit: .count()),
        HKTypeDescriptor(identifier: .bodyFatPercentage, unit: .percent()),
        HKTypeDescriptor(identifier: .walkingHeartRateAverage, unit: HKUnit(from: "count/min")),
        HKTypeDescriptor(identifier: .restingHeartRate, unit: HKUnit(from: "count/min")),
        HKTypeDescriptor(identifier: .walkingSpeed, unit: HKUnit(from: "m/s")),
        HKTypeDescriptor(identifier: .walkingStepLength, unit: .meter()),
        HKTypeDescriptor(identifier: .walkingAsymmetryPercentage, unit: .percent()),
        HKTypeDescriptor(identifier: .walkingDoubleSupportPercentage, unit: .percent()),
        HKTypeDescriptor(identifier: .environmentalAudioExposure, unit: .decibelAWeightedSoundPressureLevel()),
        HKTypeDescriptor(identifier: .headphoneAudioExposure, unit: .decibelAWeightedSoundPressureLevel()),
    ]

    static let categoryTypeIdentifiers: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis,
        .lowHeartRateEvent,
        .irregularHeartRhythmEvent,
        .highHeartRateEvent,
        .menstrualFlow,
        .intermenstrualBleeding,
    ]

    static var allReadTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        for descriptor in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: descriptor.identifier) {
                types.insert(type)
            }
        }
        for identifier in categoryTypeIdentifiers {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    /// Characteristic types (date of birth, biological sex, etc.) are queried via
    /// `HKHealthStore` directly and not as samples, but they must still be included
    /// in `requestAuthorization(read:)`.
    static var characteristicReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let dob = HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dob)
        }
        return types
    }

    /// Union of all read types (samples + characteristics) passed to
    /// `HKHealthStore.requestAuthorization(toShare:read:)`.
    static var authorizationReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = allReadTypes.reduce(into: Set<HKObjectType>()) { acc, type in
            acc.insert(type)
        }
        types.formUnion(characteristicReadTypes)
        return types
    }
}

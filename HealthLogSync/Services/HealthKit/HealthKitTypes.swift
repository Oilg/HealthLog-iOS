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
}

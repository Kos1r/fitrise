import Foundation
import HealthKit

/// Optional Apple Health integration. Every call is safe when Health is unavailable
/// or the user declined: methods simply return nil/false.
final class HealthKitService: @unchecked Sendable {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        return types
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        return types
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// Saves a strength workout. Returns true on success.
    func saveWorkout(start: Date, end: Date, totalVolumeKg: Double) async -> Bool {
        guard isAvailable, end > start else { return false }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([
                HKMetadataKeyIndoorWorkout: true,
                "LiftFuelTotalVolumeKg": totalVolumeKg
            ])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }

    func saveBodyWeight(_ kg: Double, date: Date) async -> Bool {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return false }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: date, end: date)
        do {
            try await store.save(sample)
            return true
        } catch {
            return false
        }
    }

    func latestBodyWeight() async -> (kg: Double, date: Date)? {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.endDate)
    }

    func stepsToday(calendar: Calendar = .current) async -> Double? {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = calendar.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        guard let statistics = try? await descriptor.result(for: store) else { return nil }
        return statistics.sumQuantity()?.doubleValue(for: .count())
    }
}

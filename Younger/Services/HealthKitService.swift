import Foundation
import HealthKit
@preconcurrency import CoreBluetooth

actor HealthKitService {
    private let store = HKHealthStore()
    private let calendar = Calendar.current

    static let shared = HealthKitService()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch where isHealthKitNoDataError(error) {
            // HealthKit can report no matching data even though read access was granted.
        }
    }

    func fetchToday() async throws -> [String: Double] {
        guard isAvailable else { throw HealthKitError.unavailable }

        async let steps = cumulative(.stepCount, unit: .count())
        async let energy = cumulative(.activeEnergyBurned, unit: .kilocalorie())
        async let exercise = cumulative(.appleExerciseTime, unit: .minute())
        async let stand = cumulative(.appleStandTime, unit: .minute())
        async let distance = cumulative(.distanceWalkingRunning, unit: .meterUnit(with: .kilo))
        async let flights = cumulative(.flightsClimbed, unit: .count())
        async let mindful = categoryDuration(.mindfulSession)
        async let sleep = sleepHours()
        async let hrv = latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let restingHeartRate = latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let respiratoryRate = latest(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let oxygen = latest(.oxygenSaturation, unit: .percent())
        async let vo2 = latest(.vo2Max, unit: HKUnit(from: "ml/kg*min"))
        async let leanBodyMass = latest(.leanBodyMass, unit: .gramUnit(with: .kilo))
        async let zoneMinutes = activeHeartRateMinutes()

        return [
            "steps": try await steps,
            "activeEnergy": try await energy,
            "exerciseMinutes": try await exercise,
            "standHours": try await stand / 60,
            "distance": try await distance,
            "flights": try await flights,
            "mindfulMinutes": try await mindful,
            "sleepHours": try await sleep,
            "hrv": try await hrv,
            "restingHeartRate": try await restingHeartRate,
            "respiratoryRate": try await respiratoryRate,
            "oxygenSaturation": try await oxygen * 100,
            "vo2Max": try await vo2,
            "leanBodyMass": try await leanBodyMass,
            "zoneMinutes": try await zoneMinutes
        ]
    }

    func latestHeartRate() async throws -> HeartRateReading? {
        guard isAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }
        let start = calendar.date(byAdding: .day, value: -1, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if isHealthKitNoDataError(error) {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: HeartRateReading(
                    bpm: sample.quantity.doubleValue(for: unit),
                    date: sample.endDate,
                    source: "Apple Health"
                ))
            }
            store.execute(query)
        }
    }

    func estimatedMaximumHeartRate() -> Double {
        guard let components = try? store.dateOfBirthComponents(),
              let birthday = calendar.date(from: components),
              let age = calendar.dateComponents([.year], from: birthday, to: Date()).year else {
            return 185
        }
        return Double(220 - age)
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        let quantities: [HKQuantityTypeIdentifier] = [
            .stepCount, .distanceWalkingRunning, .distanceCycling, .swimmingStrokeCount,
            .flightsClimbed, .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime,
            .appleStandTime, .heartRate, .restingHeartRate, .walkingHeartRateAverage,
            .heartRateVariabilitySDNN, .heartRateRecoveryOneMinute, .respiratoryRate,
            .oxygenSaturation, .vo2Max, .bodyMass, .bodyMassIndex, .bodyFatPercentage,
            .leanBodyMass, .height, .waistCircumference, .walkingSpeed, .walkingStepLength,
            .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage,
            .stairAscentSpeed, .stairDescentSpeed, .sixMinuteWalkTestDistance,
            .appleWalkingSteadiness, .dietaryWater, .dietaryEnergyConsumed,
            .environmentalAudioExposure, .headphoneAudioExposure, .bodyTemperature,
            .bloodGlucose, .bloodPressureSystolic, .bloodPressureDiastolic
        ]
        quantities.compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }

        let categories: [HKCategoryTypeIdentifier] = [
            .sleepAnalysis, .mindfulSession, .highHeartRateEvent, .lowHeartRateEvent,
            .irregularHeartRhythmEvent, .appleWalkingSteadinessEvent,
            .toothbrushingEvent, .handwashingEvent
        ]
        categories.compactMap { HKObjectType.categoryType(forIdentifier: $0) }.forEach { types.insert($0) }

        types.insert(HKObjectType.workoutType())
        types.insert(HKObjectType.activitySummaryType())
        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirth)
        }
        if let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            types.insert(biologicalSex)
        }
        return types
    }

    private func cumulative(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    if isHealthKitNoDataError(error) {
                        continuation.resume(returning: 0)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let start = calendar.date(byAdding: .day, value: -14, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if isHealthKitNoDataError(error) {
                        continuation.resume(returning: 0)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func categoryDuration(_ identifier: HKCategoryTypeIdentifier) async throws -> Double {
        guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else { return 0 }
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) {
                _, samples, error in
                if let error {
                    if isHealthKitNoDataError(error) {
                        continuation.resume(returning: 0)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let minutes = (samples ?? []).reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60 }
                continuation.resume(returning: minutes)
            }
            store.execute(query)
        }
    }

    private func sleepHours() async throws -> Double {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let start = calendar.date(byAdding: .hour, value: -18, to: calendar.startOfDay(for: Date())) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) {
                _, samples, error in
                if let error {
                    if isHealthKitNoDataError(error) {
                        continuation.resume(returning: 0)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let asleepValues = Set([
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ])
                let hours = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 3600 }
                continuation.resume(returning: hours)
            }
            store.execute(query)
        }
    }

    private func activeHeartRateMinutes() async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let start = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let bpm = HKUnit.count().unitDivided(by: .minute())

        let age: Int
        if let components = try? store.dateOfBirthComponents(),
           let birthday = calendar.date(from: components) {
            age = calendar.dateComponents([.year], from: birthday, to: Date()).year ?? 35
        } else {
            age = 35
        }
        let zoneTwoFloor = Double(220 - age) * 0.60

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) {
                _, samples, error in
                if let error {
                    if isHealthKitNoDataError(error) {
                        continuation.resume(returning: 0)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let heartRates = samples as? [HKQuantitySample] ?? []
                var seconds = 0.0
                for index in heartRates.indices {
                    guard heartRates[index].quantity.doubleValue(for: bpm) >= zoneTwoFloor else { continue }
                    let nextDate = index + 1 < heartRates.count ? heartRates[index + 1].startDate : heartRates[index].endDate
                    seconds += min(max(nextDate.timeIntervalSince(heartRates[index].startDate), 1), 300)
                }
                continuation.resume(returning: seconds / 60)
            }
            store.execute(query)
        }
    }
}

struct HeartRateReading {
    let bpm: Double
    let date: Date
    let source: String
}

@MainActor
final class WhoopHeartRateMonitor: NSObject, ObservableObject {
    @Published private(set) var reading: HeartRateReading?
    @Published private(set) var status = "Looking for WHOOP"

    private static let heartRateService = CBUUID(string: "180D")
    private static let heartRateMeasurement = CBUUID(string: "2A37")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var shouldScan = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        shouldScan = true
        beginScanningIfReady()
    }

    func stop() {
        shouldScan = false
        central.stopScan()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func beginScanningIfReady() {
        guard shouldScan, central.state == .poweredOn else { return }
        status = "Looking for WHOOP"

        if let connected = central.retrieveConnectedPeripherals(withServices: [Self.heartRateService]).first {
            connect(connected)
            return
        }

        central.scanForPeripherals(
            withServices: [Self.heartRateService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connect(_ peripheral: CBPeripheral) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        status = "Connecting to \(peripheral.name ?? "WHOOP")"
        central.connect(peripheral)
    }

    private func parseHeartRate(_ data: Data) -> Double? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data)
        if bytes[0] & 0x01 == 0 {
            return Double(bytes[1])
        }
        guard bytes.count >= 3 else { return nil }
        return Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
    }
}

extension WhoopHeartRateMonitor: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScanningIfReady()
        case .poweredOff:
            status = "Bluetooth is off"
        case .unauthorized:
            status = "Bluetooth permission is required"
        case .unsupported:
            status = "Bluetooth is unavailable"
        default:
            status = "Waiting for Bluetooth"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected to \(peripheral.name ?? "WHOOP")"
        peripheral.discoverServices([Self.heartRateService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        status = "Couldn’t connect. Retrying"
        beginScanningIfReady()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        reading = nil
        status = "WHOOP disconnected. Retrying"
        beginScanningIfReady()
    }
}

extension WhoopHeartRateMonitor: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            status = "Couldn’t read WHOOP services"
            return
        }
        peripheral.services?
            .filter { $0.uuid == Self.heartRateService }
            .forEach { peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: $0) }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: {
                  $0.uuid == Self.heartRateMeasurement
              }) else {
            status = "Heart-rate broadcast was not found"
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
        status = "Waiting for heart rate"
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              let data = characteristic.value,
              let bpm = parseHeartRate(data) else {
            return
        }
        reading = HeartRateReading(
            bpm: bpm,
            date: Date(),
            source: peripheral.name ?? "WHOOP"
        )
        status = "Live from \(peripheral.name ?? "WHOOP")"
    }
}

private func isHealthKitNoDataError(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == HKErrorDomain && error.code == HKError.Code.errorNoData.rawValue
}

enum HealthKitError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Apple Health data is not available on this device."
    }
}

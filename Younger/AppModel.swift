import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var metrics: [DailyMetric] = []
    @Published var trend: [TrendDay] = []
    @Published var dataPoints: [HealthDataPoint] = []
    @Published var isLoading = false
    @Published var healthConnected = false
    @Published var whoopConnected = false
    @Published var showingHealthPermission = false
    @Published var lastUpdated = Date()
    @Published var errorMessage: String?
    @Published var useDemoData = true

    private let healthKit = HealthKitService.shared
    private let whoop = WhoopService.shared
    private let whoopOAuth = WhoopOAuthCoordinator.shared
    private var latestHealthValues: [String: Double]?
    private var latestWhoopSnapshot: WhoopSnapshot?

    var score: Int {
        let totalWeight = metrics.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let weighted = metrics.reduce(0) { $0 + ($1.progress * $1.weight) }
        return Int((weighted / totalWeight * 100).rounded())
    }

    var greenCount: Int { metrics.filter { $0.status == .green }.count }
    var focusMetrics: [DailyMetric] {
        metrics.filter { $0.status != .green }.sorted { $0.progress < $1.progress }
    }

    func start() async {
        whoopConnected = await whoop.hasToken
        loadDemoData()
        if whoopConnected {
            await refreshWhoop()
        }
    }

    func connectHealth() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await healthKit.requestAuthorization()
            healthConnected = true
            useDemoData = false
            try await refreshHealth()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connectWhoop() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ticket = try await whoopOAuth.authenticate()
            try await whoop.exchangeTicket(ticket)
            whoopConnected = true
            useDemoData = false
            await refreshWhoop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnectWhoop() async {
        await whoop.disconnect()
        whoopConnected = false
        loadDemoData()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        if healthConnected {
            do {
                try await refreshHealth()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if whoopConnected {
            await refreshWhoop()
        }
        lastUpdated = Date()
    }

    func toggleDemo(_ enabled: Bool) {
        useDemoData = enabled
        if enabled { loadDemoData() }
    }

    func updateTarget(for id: String, to target: Double) {
        guard let index = metrics.firstIndex(where: { $0.id == id }) else { return }
        metrics[index].target = target
    }

    private func refreshHealth() async throws {
        let values = try await healthKit.fetchToday()
        replaceMetric("steps", value: values["steps"])
        replaceMetric("activeEnergy", value: values["activeEnergy"])
        replaceMetric("exercise", value: values["exerciseMinutes"])
        replaceMetric("stand", value: values["standHours"])
        replaceMetric("sleep", value: values["sleepHours"])
        replaceMetric("zoneMinutes", value: values["zoneMinutes"])
        replaceMetric("mindful", value: values["mindfulMinutes"])
        latestHealthValues = values
        rebuildDataPoints(health: latestHealthValues, whoop: latestWhoopSnapshot)
    }

    private func refreshWhoop() async {
        do {
            let snapshot = try await whoop.fetchSnapshot()
            replaceMetric("recovery", value: snapshot.recoveryScore)
            replaceMetric("sleep", value: snapshot.sleepHours, source: .whoop)
            replaceMetric("zoneMinutes", value: snapshot.zoneMinutes, source: .whoop)
            latestWhoopSnapshot = snapshot
            rebuildDataPoints(health: latestHealthValues, whoop: latestWhoopSnapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceMetric(_ id: String, value: Double?, source: MetricSource? = nil) {
        guard let value, value >= 0, let index = metrics.firstIndex(where: { $0.id == id }) else { return }
        var metric = metrics[index]
        metric.value = value
        if let source {
            metric = DailyMetric(
                id: metric.id, title: metric.title, category: metric.category, source: source,
                value: value, target: metric.target, unit: metric.unit, weight: metric.weight,
                icon: metric.icon, action: metric.action, decimals: metric.decimals
            )
        }
        metrics[index] = metric
    }

    private func loadDemoData() {
        metrics = [
            DailyMetric(id: "recovery", title: "Recovery", category: .recover, source: .whoop, value: 72, target: 67, unit: "%", weight: 1.4, icon: "heart.fill", action: "Protect your recovery with a lighter evening."),
            DailyMetric(id: "sleep", title: "Sleep", category: .sleep, source: .whoop, value: 7.3, target: 8, unit: "hours", weight: 1.4, icon: "moon.fill", action: "Aim for 42 more minutes tonight.", decimals: 1),
            DailyMetric(id: "steps", title: "Steps", category: .move, source: .appleHealth, value: 4_286, target: 10_000, unit: "steps", weight: 1.1, icon: "figure.walk", action: "A 38-minute walk closes most of this gap."),
            DailyMetric(id: "zoneMinutes", title: "Heart zones", category: .move, source: .appleHealth, value: 18, target: 30, unit: "min", weight: 1.2, icon: "waveform.path.ecg", action: "Add 12 minutes in zone 2 or higher."),
            DailyMetric(id: "activeEnergy", title: "Active energy", category: .move, source: .appleHealth, value: 410, target: 600, unit: "kcal", weight: 0.8, icon: "flame.fill", action: "One brisk walk adds about 150 calories."),
            DailyMetric(id: "exercise", title: "Exercise", category: .move, source: .appleHealth, value: 32, target: 45, unit: "min", weight: 0.8, icon: "figure.strengthtraining.traditional", action: "Move with intent for 13 more minutes."),
            DailyMetric(id: "stand", title: "Stand", category: .move, source: .appleHealth, value: 9, target: 12, unit: "hours", weight: 0.5, icon: "figure.stand", action: "Stand and move during 3 more hours."),
            DailyMetric(id: "mindful", title: "Reset", category: .mind, source: .appleHealth, value: 10, target: 10, unit: "min", weight: 0.6, icon: "wind", action: "Your nervous-system reset is complete.")
        ]

        trend = (0..<14).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset - 13, to: Date()) ?? Date()
            let scores = [58, 64, 71, 68, 76, 82, 79, 74, 86, 81, 77, 84, 72, 76]
            return TrendDay(date: date, score: Double(scores[offset]))
        }

        latestHealthValues = [
            "steps": 4286, "activeEnergy": 410, "exerciseMinutes": 32, "standHours": 9,
            "distance": 3.4, "flights": 6, "mindfulMinutes": 10, "sleepHours": 7.3,
            "hrv": 54, "restingHeartRate": 52, "respiratoryRate": 14.2,
            "oxygenSaturation": 97.4, "vo2Max": 46.8, "zoneMinutes": 18
        ]
        latestWhoopSnapshot = WhoopSnapshot(
            recoveryScore: 72, strain: 8.6, sleepHours: 7.3, sleepPerformance: 86,
            hrv: 54, restingHeartRate: 52, respiratoryRate: 14.2,
            oxygenSaturation: 97.4, skinTemperature: 33.6, zoneMinutes: 18
        )
        rebuildDataPoints(health: latestHealthValues, whoop: latestWhoopSnapshot)
    }

    private func rebuildDataPoints(health: [String: Double]?, whoop: WhoopSnapshot?) {
        var points: [HealthDataPoint] = []
        if let health {
            let definitions: [(String, String, String, String)] = [
                ("Steps", "steps", "Activity", "steps"),
                ("Active energy", "activeEnergy", "Activity", "kcal"),
                ("Exercise", "exerciseMinutes", "Activity", "min"),
                ("Stand", "standHours", "Activity", "hr"),
                ("Walking distance", "distance", "Mobility", "km"),
                ("Flights climbed", "flights", "Mobility", "flights"),
                ("Sleep", "sleepHours", "Sleep", "hr"),
                ("HRV", "hrv", "Vitals", "ms"),
                ("Resting heart rate", "restingHeartRate", "Vitals", "bpm"),
                ("Respiratory rate", "respiratoryRate", "Vitals", "br/min"),
                ("Blood oxygen", "oxygenSaturation", "Vitals", "%"),
                ("VO₂ max", "vo2Max", "Fitness", "ml/kg/min"),
                ("Heart-zone time", "zoneMinutes", "Fitness", "min"),
                ("Mindful time", "mindfulMinutes", "Mind", "min")
            ]
            points += definitions.compactMap { name, key, category, unit in
                guard let value = health[key] else { return nil }
                return HealthDataPoint(name: name, value: "\(value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))) \(unit)", source: .appleHealth, category: category, updated: "Today")
            }
        }
        if let whoop {
            let definitions: [(String, Double?, String, String)] = [
                ("Recovery", whoop.recoveryScore, "Recovery", "%"),
                ("Day strain", whoop.strain, "Activity", ""),
                ("Sleep performance", whoop.sleepPerformance, "Sleep", "%"),
                ("HRV (RMSSD)", whoop.hrv, "Vitals", "ms"),
                ("Resting heart rate", whoop.restingHeartRate, "Vitals", "bpm"),
                ("Skin temperature", whoop.skinTemperature, "Vitals", "°C")
            ]
            points += definitions.compactMap { name, value, category, unit in
                guard let value else { return nil }
                return HealthDataPoint(name: name, value: "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)", source: .whoop, category: category, updated: "Latest")
            }
        }
        dataPoints = points
    }
}

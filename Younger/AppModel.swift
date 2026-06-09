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
    @Published var errorTitle = "Something went wrong"
    @Published var errorMessage: String?
    @Published var useDemoData = false
    @Published var metricHistory: [MetricHistoryPoint] = []
    @Published var workoutSummaries: [WorkoutSummary] = []

    private let healthKit = HealthKitService.shared
    private let whoop = WhoopService.shared
    private let whoopOAuth = WhoopOAuthCoordinator.shared
    private var latestHealthValues: [String: Double]?
    private var latestWhoopSnapshot: WhoopSnapshot?
    private let healthConnectionKey = "appleHealthConnected"
    private let historyKey = "metricHistory"
    private let workoutSummaryKey = "workoutSummaries"

    var visibleMetrics: [DailyMetric] {
        metrics.filter { metric in
            if useDemoData { return true }
            return switch metric.source {
            case .appleHealth: healthConnected
            case .whoop: whoopConnected
            case .younger: true
            }
        }
    }

    var score: Int {
        let scoredMetrics = visibleMetrics.filter(\.contributesToScore)
        let totalWeight = scoredMetrics.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let weighted = scoredMetrics.reduce(0) { $0 + ($1.progress * $1.weight) }
        return Int((weighted / totalWeight * 100).rounded())
    }

    var greenCount: Int { visibleMetrics.filter { $0.status == .green }.count }
    var focusMetrics: [DailyMetric] {
        visibleMetrics
            .filter { $0.contributesToScore && $0.status != .green }
            .sorted { $0.progress < $1.progress }
    }

    var dayModeTitle: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "Morning check-in"
        case 11..<18: "Build your day"
        default: "Finish well"
        }
    }

    var dayModeDetail: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11:
            return trainingRecommendation
        case 11..<18:
            return focusMetrics.first?.action ?? "Maintain the habits already in the green."
        default:
            if let sleep = metrics.first(where: { $0.id == "sleep" }), sleep.progress < 1 {
                return "Protect tonight’s sleep window and keep late training easy."
            }
            return "Your main work is done. Favor recovery and a consistent bedtime."
        }
    }

    var trainingRecommendation: String {
        guard let recovery = latestWhoopSnapshot?.recoveryScore else {
            return "Use an easy session until recovery data is available."
        }
        if recovery < 34 {
            return "Recovery is low. Choose a recovery walk or rest instead of hard intervals."
        }
        if recovery < 67 {
            return "Recovery is moderate. Zone 2 or controlled strength work fits today."
        }
        return "Recovery supports a harder session if you feel well."
    }

    var dailyActions: [DailyAction] {
        var actions = focusMetrics.prefix(3).enumerated().map { index, metric in
            DailyAction(
                id: metric.id,
                title: actionTitle(for: metric),
                detail: metric.action,
                icon: metric.icon,
                color: metric.status.color,
                priority: index
            )
        }
        if actions.isEmpty {
            actions.append(DailyAction(
                id: "maintain",
                title: "Maintain the green",
                detail: "Your available daily signals are on target.",
                icon: "checkmark.circle.fill",
                color: YoungerTheme.mint,
                priority: 0
            ))
        }
        return actions
    }

    var healthNotices: [HealthNotice] {
        guard let snapshot = latestWhoopSnapshot else { return [] }
        var notices: [HealthNotice] = []
        if let oxygen = snapshot.oxygenSaturation, oxygen > 0, oxygen < 92 {
            notices.append(HealthNotice(
                id: "oxygen", title: "Blood oxygen is lower than expected",
                detail: "Check the reading again. Seek medical guidance if it remains low or you feel unwell.",
                icon: "lungs.fill", color: YoungerTheme.coral
            ))
        }
        if let respiratory = snapshot.respiratoryRate, respiratory > 20 {
            notices.append(HealthNotice(
                id: "respiratory", title: "Respiratory rate is elevated",
                detail: "Consider an easier day and watch whether the pattern continues.",
                icon: "wind", color: YoungerTheme.gold
            ))
        }
        if let recovery = snapshot.recoveryScore, recovery < 34 {
            notices.append(HealthNotice(
                id: "recovery", title: "Recovery is low",
                detail: "This is a training signal, not a diagnosis. Favor rest or easy movement today.",
                icon: "bed.double.fill", color: YoungerTheme.gold
            ))
        }
        return notices
    }

    func start() async {
        healthConnected = UserDefaults.standard.bool(forKey: healthConnectionKey)
        whoopConnected = await whoop.hasToken
        loadLiveMetricTemplates()
        loadPersistedData()
        if healthConnected {
            try? await refreshHealth()
        }
        if whoopConnected {
            await refreshWhoop()
        }
    }

    func connectHealth() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if useDemoData {
                loadLiveMetricTemplates()
                useDemoData = false
            }
            try await healthKit.requestAuthorization()
            healthConnected = true
            UserDefaults.standard.set(true, forKey: healthConnectionKey)
            try await refreshHealth()
        } catch {
            errorTitle = "Apple Health connection"
            errorMessage = error.localizedDescription
        }
    }

    func disconnectHealth() {
        healthConnected = false
        UserDefaults.standard.set(false, forKey: healthConnectionKey)
        latestHealthValues = nil

        for id in ["steps", "vo2Max", "leanBodyMass"] {
            replaceMetric(id, value: nil, source: .appleHealth)
        }
        rebuildDataPoints(health: nil, whoop: whoopConnected ? latestWhoopSnapshot : nil)
    }

    func connectWhoop() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if useDemoData {
                loadLiveMetricTemplates()
                useDemoData = false
            }
            let ticket = try await whoopOAuth.authenticate()
            try await whoop.exchangeTicket(ticket)
            whoopConnected = true
            await refreshWhoop()
        } catch {
            errorTitle = "WHOOP connection"
            errorMessage = error.localizedDescription
        }
    }

    func disconnectWhoop() async {
        await whoop.disconnect()
        whoopConnected = false
        latestWhoopSnapshot = nil
        for id in ["sleepConsistency", "sleep", "zoneOneToThree", "zoneFourToFive", "strength", "restingHeartRate"] {
            replaceMetric(id, value: nil, source: .whoop)
        }
        rebuildDataPoints(health: healthConnected ? latestHealthValues : nil, whoop: nil)
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        if healthConnected {
            do {
                try await refreshHealth()
            } catch {
                errorTitle = "Apple Health refresh"
                errorMessage = error.localizedDescription
            }
        }
        if whoopConnected {
            await refreshWhoop()
        }
        lastUpdated = Date()
    }

    func refreshMetric(_ id: String) async {
        if let metric = metrics.first(where: { $0.id == id }) {
            switch metric.source {
            case .appleHealth where healthConnected:
                try? await refreshHealth()
            case .whoop where whoopConnected:
                await refreshWhoop()
            default:
                break
            }
        }
        lastUpdated = Date()
    }

    func history(for metricID: String, days: Int) -> [MetricHistoryPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return metricHistory
            .filter { $0.metricID == metricID && $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    func saveWorkoutSummary(_ summary: WorkoutSummary) {
        workoutSummaries.insert(summary, at: 0)
        workoutSummaries = Array(workoutSummaries.prefix(20))
        persist(workoutSummaries, key: workoutSummaryKey)
    }

    func toggleDemo(_ enabled: Bool) {
        useDemoData = enabled
        if enabled {
            loadDemoData()
        } else {
            loadLiveMetricTemplates()
            Task { await refresh() }
        }
    }

    func updateTarget(for id: String, to target: Double) {
        guard let index = metrics.firstIndex(where: { $0.id == id }) else { return }
        metrics[index].target = target
    }

    private func refreshHealth() async throws {
        let values = try await healthKit.fetchToday()
        let now = Date()
        replaceMetric("steps", value: values["steps"], updatedAt: now)
        replaceMetric("vo2Max", value: values["vo2Max"], updatedAt: now)
        replaceMetric("leanBodyMass", value: values["leanBodyMass"], updatedAt: now)
        latestHealthValues = values
        recordMetricHistory()
        rebuildDataPoints(health: latestHealthValues, whoop: latestWhoopSnapshot)
    }

    private func refreshWhoop() async {
        do {
            let snapshot = try await whoop.fetchSnapshot()
            let now = Date()
            replaceMetric("sleepConsistency", value: snapshot.sleepConsistency, updatedAt: now)
            replaceMetric("sleep", value: snapshot.sleepHours, updatedAt: now)
            replaceMetric(
                "zoneOneToThree", value: snapshot.zoneOneToThreeMinutes,
                updatedAt: now, weeklyValue: snapshot.weeklyZoneOneToThreeMinutes
            )
            replaceMetric(
                "zoneFourToFive", value: snapshot.zoneFourToFiveMinutes,
                updatedAt: now, weeklyValue: snapshot.weeklyZoneFourToFiveMinutes
            )
            replaceMetric(
                "strength", value: snapshot.strengthMinutes,
                updatedAt: now, weeklyValue: snapshot.weeklyStrengthMinutes
            )
            replaceMetric("restingHeartRate", value: snapshot.restingHeartRate, updatedAt: now)
            latestWhoopSnapshot = snapshot
            recordMetricHistory()
            rebuildDataPoints(health: latestHealthValues, whoop: latestWhoopSnapshot)
        } catch {
            errorTitle = "WHOOP refresh"
            errorMessage = error.localizedDescription
        }
    }

    private func replaceMetric(
        _ id: String,
        value: Double?,
        source: MetricSource? = nil,
        updatedAt: Date? = nil,
        weeklyValue: Double? = nil
    ) {
        guard value.map({ $0 >= 0 }) ?? true,
              let index = metrics.firstIndex(where: { $0.id == id }) else { return }
        var metric = metrics[index]
        metric.value = value
        metric.updatedAt = updatedAt ?? metric.updatedAt
        if let weeklyValue { metric.weeklyValue = weeklyValue }
        if let source {
            metric = DailyMetric(
                id: metric.id, title: metric.title, category: metric.category, source: source,
                value: value, target: metric.target, unit: metric.unit, weight: metric.weight,
                icon: metric.icon, action: metric.action, decimals: metric.decimals,
                goal: metric.goal, updatedAt: metric.updatedAt,
                weeklyTarget: metric.weeklyTarget, weeklyValue: metric.weeklyValue
            )
        }
        metrics[index] = metric
    }

    private func loadLiveMetricTemplates() {
        metrics = [
            DailyMetric(id: "sleepConsistency", title: "Sleep consistency", category: .sleep, source: .whoop, value: nil, target: 85, unit: "%", weight: 1.2, icon: "bed.double.fill", action: "Keep bedtime and wake time close to your usual schedule."),
            DailyMetric(id: "sleep", title: "Hours of sleep", category: .sleep, source: .whoop, value: nil, target: 7, unit: "hours", weight: 1.2, icon: "moon.fill", action: "Protect enough time for at least 7 hours of sleep.", decimals: 1),
            DailyMetric(id: "steps", title: "Steps", category: .move, source: .appleHealth, value: nil, target: 10_000, unit: "steps", weight: 1, icon: "figure.walk", action: "Add a walk today to close your step gap."),
            DailyMetric(id: "zoneOneToThree", title: "HR zones 1–3", category: .move, source: .whoop, value: nil, target: 38, unit: "min", weight: 1, icon: "figure.run", action: "Build easy-to-moderate aerobic time today.", weeklyTarget: 266),
            DailyMetric(id: "zoneFourToFive", title: "HR zones 4–5", category: .move, source: .whoop, value: nil, target: 9, unit: "min", weight: 1, icon: "bolt.heart.fill", action: "Add a short hard effort if recovery supports it.", weeklyTarget: 60),
            DailyMetric(id: "strength", title: "Strength activity", category: .move, source: .whoop, value: nil, target: 26, unit: "min", weight: 1, icon: "dumbbell.fill", action: "Log strength work in WHOOP today.", weeklyTarget: 180),
            DailyMetric(id: "vo2Max", title: "VO₂ max", category: .recover, source: .appleHealth, value: nil, target: 45, unit: "ml/kg/min", weight: 1.3, icon: "lungs.fill", action: "VO₂ max changes slowly; use zone 4–5 work to train it.", decimals: 1),
            DailyMetric(id: "restingHeartRate", title: "Resting heart rate", category: .recover, source: .whoop, value: nil, target: 60, unit: "bpm", weight: 1.1, icon: "heart.fill", action: "Recovery, sleep, and aerobic fitness can improve resting heart rate.", goal: .atMost),
            DailyMetric(id: "leanBodyMass", title: "Lean body mass", category: .recover, source: .appleHealth, value: nil, target: 0, unit: "kg", weight: 0, icon: "figure.strengthtraining.traditional", action: "Track the trend and support it with resistance training and nutrition.", decimals: 1, goal: .informational)
        ]
    }

    private func loadDemoData() {
        metrics = [
            DailyMetric(id: "sleepConsistency", title: "Sleep consistency", category: .sleep, source: .whoop, value: 79, target: 85, unit: "%", weight: 1.2, icon: "bed.double.fill", action: "Keep bedtime and wake time close to your usual schedule."),
            DailyMetric(id: "sleep", title: "Hours of sleep", category: .sleep, source: .whoop, value: 7.5, target: 7, unit: "hours", weight: 1.2, icon: "moon.fill", action: "Protect enough time for at least 7 hours of sleep.", decimals: 1),
            DailyMetric(id: "steps", title: "Steps", category: .move, source: .appleHealth, value: 4_286, target: 10_000, unit: "steps", weight: 1, icon: "figure.walk", action: "Add a walk today to close your step gap."),
            DailyMetric(id: "zoneOneToThree", title: "HR zones 1–3", category: .move, source: .whoop, value: 28, target: 38, unit: "min", weight: 1, icon: "figure.run", action: "Build easy-to-moderate aerobic time today."),
            DailyMetric(id: "zoneFourToFive", title: "HR zones 4–5", category: .move, source: .whoop, value: 4, target: 9, unit: "min", weight: 1, icon: "bolt.heart.fill", action: "Add a short hard effort if recovery supports it."),
            DailyMetric(id: "strength", title: "Strength activity", category: .move, source: .whoop, value: 20, target: 26, unit: "min", weight: 1, icon: "dumbbell.fill", action: "Log strength work in WHOOP today."),
            DailyMetric(id: "vo2Max", title: "VO₂ max", category: .recover, source: .appleHealth, value: 46.8, target: 45, unit: "ml/kg/min", weight: 1.3, icon: "lungs.fill", action: "VO₂ max changes slowly; use zone 4–5 work to train it.", decimals: 1),
            DailyMetric(id: "restingHeartRate", title: "Resting heart rate", category: .recover, source: .whoop, value: 52, target: 60, unit: "bpm", weight: 1.1, icon: "heart.fill", action: "Recovery, sleep, and aerobic fitness can improve resting heart rate.", goal: .atMost),
            DailyMetric(id: "leanBodyMass", title: "Lean body mass", category: .recover, source: .appleHealth, value: 62.5, target: 0, unit: "kg", weight: 0, icon: "figure.strengthtraining.traditional", action: "Track the trend and support it with resistance training and nutrition.", decimals: 1, goal: .informational)
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
            "oxygenSaturation": 97.4, "vo2Max": 46.8, "leanBodyMass": 62.5,
            "zoneMinutes": 18
        ]
        latestWhoopSnapshot = WhoopSnapshot(
            recoveryScore: 72, strain: 8.6, sleepHours: 7.3, sleepPerformance: 86,
            hrv: 54, restingHeartRate: 52, respiratoryRate: 14.2,
            oxygenSaturation: 97.4, skinTemperature: 33.6, zoneMinutes: 32,
            sleepConsistency: 79, zoneOneToThreeMinutes: 28,
            zoneFourToFiveMinutes: 4, strengthMinutes: 20,
            weeklyZoneOneToThreeMinutes: 142,
            weeklyZoneFourToFiveMinutes: 22, weeklyStrengthMinutes: 70
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
                return HealthDataPoint(name: name, value: "\(value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))) \(unit)", source: .appleHealth, category: category, updated: "Synced \(Date().formatted(date: .omitted, time: .shortened))")
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
                return HealthDataPoint(name: name, value: "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)", source: .whoop, category: category, updated: "Synced \(Date().formatted(date: .omitted, time: .shortened))")
            }
        }
        dataPoints = points
    }

    private func actionTitle(for metric: DailyMetric) -> String {
        guard let value = metric.value else { return "Connect \(metric.source.rawValue)" }
        switch metric.goal {
        case .atLeast:
            let remaining = max(metric.target - value, 0)
            return remaining > 0 ?
                "\(remaining.formatted(.number.precision(.fractionLength(metric.decimals)))) \(metric.unit) remaining" :
                "\(metric.title) is complete"
        case .atMost:
            return metric.status == .green ? "\(metric.title) is on target" : "Prioritize recovery"
        case .informational:
            return "Track \(metric.title.lowercased())"
        }
    }

    private func recordMetricHistory() {
        let today = Calendar.current.startOfDay(for: Date())
        for metric in metrics {
            guard let value = metric.value else { continue }
            metricHistory.removeAll {
                $0.metricID == metric.id && Calendar.current.isDate($0.date, inSameDayAs: today)
            }
            metricHistory.append(MetricHistoryPoint(metricID: metric.id, date: today, value: value))
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: today) ?? .distantPast
        metricHistory.removeAll { $0.date < cutoff }
        persist(metricHistory, key: historyKey)
        rebuildTrendFromHistory()
    }

    private func loadPersistedData() {
        metricHistory = load([MetricHistoryPoint].self, key: historyKey) ?? []
        workoutSummaries = load([WorkoutSummary].self, key: workoutSummaryKey) ?? []
        rebuildTrendFromHistory()
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func rebuildTrendFromHistory() {
        let grouped = Dictionary(grouping: metricHistory) {
            Calendar.current.startOfDay(for: $0.date)
        }
        trend = grouped.compactMap { date, points in
            let progress = points.compactMap { point -> Double? in
                guard let metric = metrics.first(where: { $0.id == point.metricID }),
                      metric.target > 0, metric.goal != .informational else {
                    return nil
                }
                if metric.goal == .atMost {
                    guard point.value > 0 else { return nil }
                    return min(metric.target / point.value, 1)
                }
                return min(point.value / metric.target, 1)
            }
            guard !progress.isEmpty else { return nil }
            return TrendDay(date: date, score: progress.reduce(0, +) / Double(progress.count) * 100)
        }
        .sorted { $0.date < $1.date }
    }
}

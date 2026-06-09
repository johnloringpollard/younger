import Foundation
import SwiftUI

enum MetricSource: String, CaseIterable, Codable {
    case appleHealth = "Apple Health"
    case whoop = "WHOOP"
    case younger = "Younger"

    var icon: String {
        switch self {
        case .appleHealth: "heart.fill"
        case .whoop: "waveform.path.ecg"
        case .younger: "sparkles"
        }
    }
}

enum MetricCategory: String, CaseIterable, Identifiable {
    case move = "Move"
    case recover = "Recover"
    case sleep = "Sleep"
    case mind = "Mind"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .move: "figure.run"
        case .recover: "heart.text.square.fill"
        case .sleep: "moon.stars.fill"
        case .mind: "brain.head.profile"
        }
    }
}

enum MetricStatus {
    case unavailable
    case red
    case yellow
    case green

    var color: Color {
        switch self {
        case .unavailable: YoungerTheme.secondaryText
        case .red: YoungerTheme.coral
        case .yellow: YoungerTheme.gold
        case .green: YoungerTheme.mint
        }
    }

    var label: String {
        switch self {
        case .unavailable: "Not available"
        case .red: "Needs attention"
        case .yellow: "Getting closer"
        case .green: "On target"
        }
    }
}

enum MetricGoal: Codable {
    case atLeast
    case atMost
    case informational
}

struct DailyMetric: Identifiable {
    let id: String
    let title: String
    let category: MetricCategory
    let source: MetricSource
    var value: Double?
    var target: Double
    let unit: String
    let weight: Double
    let icon: String
    let action: String
    var decimals: Int = 0
    var goal: MetricGoal = .atLeast
    var updatedAt: Date?
    var weeklyTarget: Double?
    var weeklyValue: Double?

    var contributesToScore: Bool {
        value != nil && target > 0 && goal != .informational
    }

    var progress: Double {
        guard let value, target > 0 else { return 0 }
        switch goal {
        case .atLeast:
            return min(max(value / target, 0), 1)
        case .atMost:
            guard value > 0 else { return 0 }
            return min(max(target / value, 0), 1)
        case .informational:
            return 0
        }
    }

    var uncappedProgress: Double {
        guard let value, target > 0 else { return 0 }
        if goal == .atMost {
            guard value > 0 else { return 0 }
            return max(target / value, 0)
        }
        return max(value / target, 0)
    }

    var status: MetricStatus {
        guard value != nil, goal != .informational else { return .unavailable }
        if progress >= 1 { return .green }
        if progress >= 0.6 { return .yellow }
        return .red
    }

    var formattedValue: String {
        guard let value else { return "—" }
        if unit == "steps" {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }

    var formattedTarget: String {
        target.formatted(.number.precision(.fractionLength(decimals)))
    }

    var targetDescription: String {
        switch goal {
        case .atLeast: "Goal \(formattedTarget) \(unit)"
        case .atMost: "Goal ≤ \(formattedTarget) \(unit)"
        case .informational: "Track over time"
        }
    }

    var freshnessText: String {
        guard let updatedAt else { return "Waiting for data" }
        let seconds = Date().timeIntervalSince(updatedAt)
        if seconds < 30 { return "Live" }
        if seconds < 120 { return "Updated 1 minute ago" }
        if seconds < 3_600 { return "Updated \(Int(seconds / 60)) minutes ago" }
        if Calendar.current.isDateInToday(updatedAt) {
            return "Updated \(updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var weeklyPaceDescription: String? {
        guard let weeklyValue, let weeklyTarget, weeklyTarget > 0 else { return nil }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let mondayBasedDay = (weekday + 5) % 7 + 1
        let expected = weeklyTarget * Double(mondayBasedDay) / 7
        let delta = weeklyValue - expected
        if abs(delta) < weeklyTarget * 0.05 { return "On weekly pace" }
        if delta > 0 { return "Ahead of weekly pace" }
        return "Behind weekly pace"
    }
}

struct TrendDay: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double
}

struct HealthDataPoint: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let source: MetricSource
    let category: String
    let updated: String
}

struct WhoopSnapshot {
    var recoveryScore: Double?
    var strain: Double?
    var sleepHours: Double?
    var sleepPerformance: Double?
    var hrv: Double?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
    var skinTemperature: Double?
    var zoneMinutes: Double?
    var sleepConsistency: Double?
    var zoneOneToThreeMinutes: Double?
    var zoneFourToFiveMinutes: Double?
    var strengthMinutes: Double?
    var weeklyZoneOneToThreeMinutes: Double?
    var weeklyZoneFourToFiveMinutes: Double?
    var weeklyStrengthMinutes: Double?
}

struct MetricHistoryPoint: Identifiable, Codable {
    var id: String { "\(metricID)-\(date.timeIntervalSince1970)" }
    let metricID: String
    let date: Date
    let value: Double
}

struct DailyAction: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
    let priority: Int
}

struct HealthNotice: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

enum WorkoutKind: String, CaseIterable, Identifiable {
    case zoneTwo = "Zone 2"
    case intervals = "VO₂ intervals"
    case recovery = "Recovery walk"
    case strength = "Strength"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .zoneTwo: "figure.run"
        case .intervals: "bolt.heart.fill"
        case .recovery: "figure.walk"
        case .strength: "dumbbell.fill"
        }
    }

    var targetZones: ClosedRange<Int> {
        switch self {
        case .zoneTwo: 2...2
        case .intervals: 4...5
        case .recovery: 0...1
        case .strength: 1...3
        }
    }

    var durationMinutes: Int {
        switch self {
        case .zoneTwo: 30
        case .intervals: 24
        case .recovery: 20
        case .strength: 30
        }
    }

    var detail: String {
        switch self {
        case .zoneTwo: "Steady aerobic work"
        case .intervals: "Hard efforts with recovery"
        case .recovery: "Easy movement only"
        case .strength: "Track lifting time and pulse"
        }
    }
}

struct WorkoutSummary: Identifiable, Codable {
    let id: UUID
    let kindName: String
    let startedAt: Date
    let duration: TimeInterval
    let averageHeartRate: Double
    let maximumHeartRate: Double
    let zoneSeconds: [Int: TimeInterval]
    let recoveryHeartRate: Double?
}

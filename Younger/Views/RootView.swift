import SwiftUI
import UIKit

struct RootView: View {
    @State private var selection = 0

    var body: some View {
        ZStack {
            YoungerBackground()
            TabView(selection: $selection) {
                NavigationStack { WorkoutHomeView() }
                    .tabItem { Label("Workout", systemImage: "figure.run.circle.fill") }
                    .tag(0)

                NavigationStack { TodayView() }
                    .tabItem { Label("Today", systemImage: "sparkles") }
                    .tag(1)

                NavigationStack { TrendsView() }
                    .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                    .tag(2)

                NavigationStack { DataView() }
                    .tabItem { Label("Data", systemImage: "square.stack.3d.up.fill") }
                    .tag(3)

                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                    .tag(4)
            }
            .tint(YoungerTheme.mint)
        }
    }
}

private struct WorkoutHomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Train with purpose")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                    Text(model.trainingRecommendation)
                        .foregroundStyle(YoungerTheme.secondaryText)
                }

                NavigationLink {
                    HeartRateView()
                } label: {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.title2)
                            .foregroundStyle(YoungerTheme.coral)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Live heart rate").font(.headline)
                            Text("Large BPM and current zone")
                                .font(.caption)
                                .foregroundStyle(YoungerTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(18)
                    .youngerCard()
                }
                .buttonStyle(.plain)

                Text("WORKOUT TEMPLATES")
                    .font(.caption.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(YoungerTheme.secondaryText)

                ForEach(WorkoutKind.allCases) { kind in
                    NavigationLink {
                        WorkoutSessionView(kind: kind)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: kind.icon)
                                .font(.title2)
                                .foregroundStyle(YoungerTheme.mint)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(YoungerTheme.mint.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.rawValue).font(.headline)
                                Text("\(kind.durationMinutes) min · Zones \(kind.targetZones.lowerBound)–\(kind.targetZones.upperBound) · \(kind.detail)")
                                    .font(.caption)
                                    .foregroundStyle(YoungerTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(16)
                        .youngerCard()
                    }
                    .buttonStyle(.plain)
                }

                if let latest = model.workoutSummaries.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LATEST WORKOUT")
                            .font(.caption.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(YoungerTheme.secondaryText)
                        Text(latest.kindName).font(.headline)
                        Text("\(formatDuration(latest.duration)) · Avg \(Int(latest.averageHeartRate.rounded())) bpm · Max \(Int(latest.maximumHeartRate.rounded())) bpm")
                            .font(.subheadline)
                            .foregroundStyle(YoungerTheme.secondaryText)
                    }
                    .padding(18)
                    .youngerCard()
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct HeartRateView: View {
    @StateObject private var whoopMonitor = WhoopHeartRateMonitor()
    @State private var healthReading: HeartRateReading?
    @State private var maximumHeartRate = 185.0

    private var reading: HeartRateReading? {
        if let whoop = whoopMonitor.reading,
           Date().timeIntervalSince(whoop.date) < 15 {
            return whoop
        }
        return healthReading
    }

    private var zone: Int {
        guard let bpm = reading?.bpm, maximumHeartRate > 0 else { return 0 }
        return switch bpm / maximumHeartRate {
        case ..<0.50: 0
        case ..<0.60: 1
        case ..<0.70: 2
        case ..<0.80: 3
        case ..<0.90: 4
        default: 5
        }
    }

    private var zoneColor: Color {
        switch zone {
        case 0: YoungerTheme.secondaryText
        case 1: YoungerTheme.sky
        case 2: YoungerTheme.mint
        case 3: YoungerTheme.gold
        default: YoungerTheme.coral
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("HEART RATE")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(YoungerTheme.secondaryText)

                Text(reading.map { Int($0.bpm.rounded()).formatted() } ?? "—")
                    .font(.system(size: 116, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("BPM")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(YoungerTheme.secondaryText)
            }

            VStack(spacing: 6) {
                Text("ZONE \(zone)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(zoneColor)
                Text(zoneDescription)
                    .font(.headline)
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .youngerCard()

            Spacer()

            VStack(spacing: 8) {
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                if let reading {
                    Text("Updated \(reading.date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(YoungerTheme.secondaryText)
                }
                Text("For live WHOOP readings, enable Broadcast Heart Rate in the WHOOP app and keep this page open.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
        }
        .padding(24)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            maximumHeartRate = await HealthKitService.shared.estimatedMaximumHeartRate()
            whoopMonitor.start()
            while !Task.isCancelled {
                healthReading = try? await HealthKitService.shared.latestHeartRate()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onDisappear {
            whoopMonitor.stop()
        }
    }

    private var statusText: String {
        if let reading, reading.source != "Apple Health" {
            return "Live from \(reading.source)"
        }
        if reading != nil {
            return "Latest reading from Apple Health"
        }
        return whoopMonitor.status
    }

    private var zoneDescription: String {
        switch zone {
        case 0: "Easy"
        case 1: "Warm up"
        case 2: "Aerobic"
        case 3: "Tempo"
        case 4: "Threshold"
        default: "Maximum"
        }
    }
}

private struct WorkoutSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var whoopMonitor = WhoopHeartRateMonitor()
    let kind: WorkoutKind

    @State private var healthReading: HeartRateReading?
    @State private var maximumHeartRate = 185.0
    @State private var startedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var isRunning = false
    @State private var zoneSeconds: [Int: TimeInterval] = [:]
    @State private var heartRates: [Double] = []
    @State private var lastAlertAt = Date.distantPast
    @State private var completedSummary: WorkoutSummary?
    @State private var recoverySecondsRemaining: Int?
    @State private var finishingHeartRate: Double?

    private var reading: HeartRateReading? {
        if let whoop = whoopMonitor.reading,
           Date().timeIntervalSince(whoop.date) < 15 {
            return whoop
        }
        return healthReading
    }

    private var zone: Int {
        heartRateZone(reading?.bpm, maximum: maximumHeartRate)
    }

    private var inTarget: Bool {
        kind.targetZones.contains(zone)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text(kind.rawValue.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(YoungerTheme.secondaryText)

                Text(reading.map { Int($0.bpm.rounded()).formatted() } ?? "—")
                    .font(.system(size: 104, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("BPM · ZONE \(zone)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(inTarget ? YoungerTheme.mint : YoungerTheme.gold)

                VStack(spacing: 8) {
                    Text(inTarget ? "IN TARGET" : targetInstruction)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(inTarget ? YoungerTheme.mint : YoungerTheme.gold)
                    Text("Target zones \(kind.targetZones.lowerBound)–\(kind.targetZones.upperBound)")
                        .foregroundStyle(YoungerTheme.secondaryText)
                    ProgressView(value: elapsed, total: Double(kind.durationMinutes * 60))
                        .tint(inTarget ? YoungerTheme.mint : YoungerTheme.gold)
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .youngerCard()

                HStack {
                    stat("TIME", formatDuration(elapsed))
                    Divider().overlay(YoungerTheme.divider)
                    stat("TARGET TIME", formatDuration(targetZoneTime))
                    if kind == .intervals {
                        Divider().overlay(YoungerTheme.divider)
                        stat("INTERVAL", intervalLabel)
                    }
                }
                .frame(height: 68)

                HStack(spacing: 14) {
                    Button(isRunning ? "Pause" : startedAt == nil ? "Start" : "Resume") {
                        if startedAt == nil { startedAt = Date() }
                        isRunning.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(YoungerTheme.mint)

                    Button(recoverySecondsRemaining == nil ? "Finish" : "Skip recovery") {
                        if recoverySecondsRemaining == nil {
                            beginRecoveryMeasurement()
                        } else {
                            finishWorkout()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(YoungerTheme.coral)
                    .disabled(startedAt == nil)
                }

                if let recoverySecondsRemaining {
                    VStack(spacing: 7) {
                        Text("HEART-RATE RECOVERY")
                            .font(.caption.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(YoungerTheme.secondaryText)
                        Text("\(recoverySecondsRemaining)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("Keep still or walk very easily while Younger measures the one-minute drop.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(YoungerTheme.secondaryText)
                    }
                    .padding(18)
                    .youngerCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("ZONE DISTRIBUTION")
                        .font(.caption.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(YoungerTheme.secondaryText)
                    ForEach(0...5, id: \.self) { item in
                        HStack {
                            Text("Zone \(item)").frame(width: 58, alignment: .leading)
                            ProgressView(value: zoneSeconds[item, default: 0], total: max(elapsed, 1))
                            Text(formatDuration(zoneSeconds[item, default: 0]))
                                .font(.caption.monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
                        }
                        .font(.caption)
                    }
                }
                .padding(18)
                .youngerCard()

                Text("Heart-rate guidance is for fitness only. Stop if you feel pain, faintness, or unusual shortness of breath.")
                    .font(.caption)
                    .foregroundStyle(YoungerTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .navigationTitle(kind.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            maximumHeartRate = await HealthKitService.shared.estimatedMaximumHeartRate()
            whoopMonitor.start()
            while !Task.isCancelled {
                healthReading = try? await HealthKitService.shared.latestHeartRate()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard isRunning else { continue }
                elapsed += 1
                zoneSeconds[zone, default: 0] += 1
                if let bpm = reading?.bpm { heartRates.append(bpm) }
                alertForZoneIfNeeded()
                if elapsed >= Double(kind.durationMinutes * 60) {
                    beginRecoveryMeasurement()
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let remaining = recoverySecondsRemaining else { continue }
                if remaining <= 1 {
                    recoverySecondsRemaining = nil
                    finishWorkout()
                } else {
                    recoverySecondsRemaining = remaining - 1
                }
            }
        }
        .onDisappear { whoopMonitor.stop() }
        .sheet(item: $completedSummary) { summary in
            WorkoutSummaryView(summary: summary) {
                completedSummary = nil
                dismiss()
            }
        }
    }

    private var targetInstruction: String {
        zone < kind.targetZones.lowerBound ? "BUILD INTENSITY" : "EASE BACK"
    }

    private var targetZoneTime: TimeInterval {
        kind.targetZones.reduce(0) { $0 + zoneSeconds[$1, default: 0] }
    }

    private var intervalLabel: String {
        let phase = Int(elapsed) % 180
        return phase < 60 ? "WORK \(60 - phase)s" : "RECOVER \(180 - phase)s"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption2.bold()).foregroundStyle(YoungerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func alertForZoneIfNeeded() {
        guard !inTarget, Date().timeIntervalSince(lastAlertAt) > 30 else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        lastAlertAt = Date()
    }

    private func beginRecoveryMeasurement() {
        guard startedAt != nil, recoverySecondsRemaining == nil else { return }
        isRunning = false
        finishingHeartRate = reading?.bpm
        recoverySecondsRemaining = 60
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func finishWorkout() {
        guard let startedAt else { return }
        isRunning = false
        let average = heartRates.isEmpty ? 0 : heartRates.reduce(0, +) / Double(heartRates.count)
        let summary = WorkoutSummary(
            id: UUID(),
            kindName: kind.rawValue,
            startedAt: startedAt,
            duration: elapsed,
            averageHeartRate: average,
            maximumHeartRate: heartRates.max() ?? 0,
            zoneSeconds: zoneSeconds,
            recoveryHeartRate: recoveryDrop
        )
        model.saveWorkoutSummary(summary)
        completedSummary = summary
    }

    private var recoveryDrop: Double? {
        guard let finishingHeartRate, let current = reading?.bpm else { return nil }
        return max(finishingHeartRate - current, 0)
    }
}

private struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    let done: () -> Void

    var body: some View {
        ZStack {
            YoungerBackground()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(YoungerTheme.mint)
                Text("Workout complete")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(summary.kindName).foregroundStyle(YoungerTheme.secondaryText)

                HStack {
                    summaryStat("TIME", formatDuration(summary.duration))
                    summaryStat("AVERAGE", "\(Int(summary.averageHeartRate.rounded())) bpm")
                    summaryStat("MAX", "\(Int(summary.maximumHeartRate.rounded())) bpm")
                }
                .padding(18)
                .youngerCard()

                Text(summary.recoveryHeartRate.map { "One-minute heart-rate recovery: \(Int($0.rounded())) bpm" } ?? "Heart-rate recovery was unavailable because no finishing reading was received.")
                    .font(.caption)
                    .foregroundStyle(YoungerTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .tint(YoungerTheme.mint)
            }
            .padding(24)
        }
    }

    private func summaryStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.headline).minimumScaleFactor(0.7)
            Text(title).font(.caption2.bold()).foregroundStyle(YoungerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

private func heartRateZone(_ bpm: Double?, maximum: Double) -> Int {
    guard let bpm, maximum > 0 else { return 0 }
    return switch bpm / maximum {
    case ..<0.50: 0
    case ..<0.60: 1
    case ..<0.70: 2
    case ..<0.80: 3
    case ..<0.90: 4
    default: 5
    }
}

private func formatDuration(_ interval: TimeInterval) -> String {
    let total = max(Int(interval), 0)
    return String(format: "%02d:%02d", total / 60, total % 60)
}

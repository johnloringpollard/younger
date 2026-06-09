import SwiftUI

struct RootView: View {
    @State private var selection = 0

    var body: some View {
        ZStack {
            YoungerBackground()
            TabView(selection: $selection) {
                NavigationStack { HeartRateView() }
                    .tabItem { Label("Heart", systemImage: "heart.fill") }
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

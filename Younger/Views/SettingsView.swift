import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 31, weight: .bold, design: .rounded))

                section("DATA SOURCES") {
                    sourceRow(
                        title: "Apple Health",
                        detail: model.healthConnected ? "Connected" : "Activity, sleep, vitals and more",
                        icon: "heart.fill",
                        color: YoungerTheme.coral,
                        connected: model.healthConnected
                    ) {
                        if model.healthConnected {
                            model.disconnectHealth()
                        } else {
                            Task { await model.connectHealth() }
                        }
                    }
                    Divider().overlay(YoungerTheme.divider)
                    sourceRow(
                        title: "WHOOP",
                        detail: model.whoopConnected ? "Connected" : "Recovery, strain, sleep and workouts",
                        icon: "waveform.path.ecg",
                        color: YoungerTheme.sky,
                        connected: model.whoopConnected
                    ) {
                        if model.whoopConnected {
                            Task { await model.disconnectWhoop() }
                        } else {
                            Task { await model.connectWhoop() }
                        }
                    }
                    Divider().overlay(YoungerTheme.divider)
                    Text("Disconnecting Apple Health stops Younger from reading it. Revoke system permission in Health → Sharing → Apps → Younger.")
                        .font(.caption)
                        .foregroundStyle(YoungerTheme.secondaryText)
                }

                section("DEVELOPMENT") {
                    Toggle(isOn: Binding(
                        get: { model.useDemoData },
                        set: { model.toggleDemo($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Demo data").font(.headline)
                            Text("Keeps the Simulator dashboard populated")
                                .font(.caption)
                                .foregroundStyle(YoungerTheme.secondaryText)
                        }
                    }
                    .tint(YoungerTheme.mint)
                }

                section("DAILY GOALS") {
                    goalRow(id: "steps", title: "Steps", range: 5_000...20_000, step: 1_000)
                    Divider().overlay(YoungerTheme.divider)
                    goalRow(id: "sleep", title: "Sleep", range: 6...10, step: 0.5)
                    Divider().overlay(YoungerTheme.divider)
                    goalRow(id: "zoneMinutes", title: "Heart zones", range: 10...90, step: 5)
                    Divider().overlay(YoungerTheme.divider)
                    goalRow(id: "exercise", title: "Exercise", range: 15...120, step: 5)
                }

                section("HOW YOUR SCORE WORKS") {
                    Text("Each metric earns up to 100% when it reaches its daily target. Recovery and sleep carry extra weight. Younger combines those weighted results into one daily score.")
                        .font(.subheadline)
                        .foregroundStyle(YoungerTheme.secondaryText)
                    Label("No health data is sold or used for advertising.", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YoungerTheme.mint)
                }

                section("ABOUT") {
                    settingRow("Version", value: "0.1.0")
                    Divider().overlay(YoungerTheme.divider)
                    settingRow("Daily reset", value: "Midnight")
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert(model.errorTitle, isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(YoungerTheme.secondaryText)
                .tracking(1.2)
            VStack(spacing: 14) {
                content()
            }
            .padding(18)
            .youngerCard()
        }
    }

    private func sourceRow(
        title: String,
        detail: String,
        icon: String,
        color: Color,
        connected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(Circle().fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(YoungerTheme.secondaryText)
            }
            Spacer()
            if model.isLoading && !connected {
                ProgressView()
                    .tint(YoungerTheme.mint)
            } else {
                Button(connected ? "Disconnect" : "Connect", action: action)
                    .buttonStyle(.bordered)
                    .tint(connected ? YoungerTheme.mint : color)
            }
        }
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(YoungerTheme.secondaryText)
        }
    }

    @ViewBuilder
    private func goalRow(id: String, title: String, range: ClosedRange<Double>, step: Double) -> some View {
        if let metric = model.metrics.first(where: { $0.id == id }) {
            Stepper(
                value: Binding(
                    get: { metric.target },
                    set: { model.updateTarget(for: id, to: $0) }
                ),
                in: range,
                step: step
            ) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(metric.formattedTarget) \(metric.unit)")
                        .foregroundStyle(YoungerTheme.secondaryText)
                }
            }
        }
    }
}

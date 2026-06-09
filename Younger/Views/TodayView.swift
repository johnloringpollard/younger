import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header
                scoreCard
                focusCard
                metricGrid
                disclaimer
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await model.refresh() }
        .alert("Couldn’t refresh", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YoungerTheme.mint)
                    .textCase(.uppercase)
                Text("Your younger day")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(YoungerTheme.raised))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private var scoreCard: some View {
        HStack(spacing: 22) {
            ScoreRing(score: model.score)
                .frame(width: 142, height: 142)

            VStack(alignment: .leading, spacing: 10) {
                Text(scoreMessage)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(model.greenCount) of \(model.metrics.count) daily signals are green.")
                    .font(.subheadline)
                    .foregroundStyle(YoungerTheme.secondaryText)
                HStack(spacing: 6) {
                    Circle().fill(YoungerTheme.mint).frame(width: 7, height: 7)
                    Text("Updated \(model.lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(YoungerTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .youngerCard()
    }

    private var scoreMessage: String {
        switch model.score {
        case 85...: "You’re building a strong day."
        case 65...: "A few choices can turn today green."
        default: "Your body is asking for attention."
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Best next move", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(YoungerTheme.gold)
                Spacer()
                Text("RIGHT NOW")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(YoungerTheme.secondaryText)
            }

            if let metric = model.focusMetrics.first {
                Text(metric.action)
                    .font(.title3.weight(.semibold))
                ProgressView(value: metric.progress)
                    .tint(metric.status.color)
                HStack {
                    Label(metric.title, systemImage: metric.icon)
                    Spacer()
                    Text("\(metric.formattedValue) / \(metric.formattedTarget) \(metric.unit)")
                        .foregroundStyle(metric.status.color)
                }
                .font(.caption.weight(.semibold))
            } else {
                Text("Every daily signal is green. Keep the rhythm easy.")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(20)
        .youngerCard()
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(model.metrics) { metric in
                MetricCard(metric: metric)
            }
        }
    }

    private var disclaimer: some View {
        Text("Younger is a wellness guide, not a medical assessment or biological-age diagnosis. Goals should be personalized with a qualified clinician when appropriate.")
            .font(.caption)
            .foregroundStyle(YoungerTheme.secondaryText)
            .padding(.horizontal, 8)
    }
}

private struct ScoreRing: View {
    let score: Int

    var color: Color {
        if score >= 85 { return YoungerTheme.mint }
        if score >= 60 { return YoungerTheme.gold }
        return YoungerTheme.coral
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: Double(score) / 100)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.55), color], center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(score)")
                    .font(.system(size: 45, weight: .bold, design: .rounded))
                Text("TODAY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(YoungerTheme.secondaryText)
                    .tracking(1.5)
            }
        }
        .shadow(color: color.opacity(0.18), radius: 18)
    }
}

private struct MetricCard: View {
    let metric: DailyMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: metric.icon)
                    .foregroundStyle(metric.status.color)
                Spacer()
                Circle()
                    .fill(metric.status.color)
                    .frame(width: 9, height: 9)
            }
            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(YoungerTheme.secondaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.formattedValue)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                Text("of \(metric.formattedTarget) \(metric.unit)")
                    .font(.caption)
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
            ProgressView(value: metric.progress)
                .tint(metric.status.color)
            Label(metric.source.rawValue, systemImage: metric.source.icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(YoungerTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .youngerCard()
    }
}

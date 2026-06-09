import SwiftUI
import Charts

struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header
                contextCard
                dailyPlanCard
                scoreCard
                weeklyPaceCard
                notices
                metricGrid
                disclaimer
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await model.refresh() }
        .alert(model.errorTitle, isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.dayModeTitle, systemImage: contextIcon)
                .font(.headline)
                .foregroundStyle(YoungerTheme.mint)
            Text(model.dayModeDetail)
                .font(.title3.weight(.semibold))
            Text(model.trainingRecommendation)
                .font(.caption)
                .foregroundStyle(YoungerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .youngerCard()
    }

    private var contextIcon: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "sunrise.fill"
        case 11..<18: "sun.max.fill"
        default: "moon.stars.fill"
        }
    }

    private var dailyPlanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Today’s plan", systemImage: "list.bullet.clipboard.fill")
                    .font(.headline)
                Spacer()
                Text("IN ORDER")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
            ForEach(Array(model.dailyActions.enumerated()), id: \.element.id) { index, action in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline)
                        .foregroundStyle(action.color)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(action.color.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title).font(.headline)
                        Text(action.detail)
                            .font(.caption)
                            .foregroundStyle(YoungerTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: action.icon).foregroundStyle(action.color)
                }
            }
        }
        .padding(20)
        .youngerCard()
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
                Text("\(model.greenCount) of \(model.visibleMetrics.filter(\.contributesToScore).count) available signals are green.")
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

    @ViewBuilder
    private var weeklyPaceCard: some View {
        let paced = model.visibleMetrics.filter { $0.weeklyPaceDescription != nil }
        if !paced.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label("Weekly pace", systemImage: "calendar.badge.clock")
                    .font(.headline)
                ForEach(paced) { metric in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(metric.title, systemImage: metric.icon)
                            Spacer()
                            Text(metric.weeklyPaceDescription ?? "")
                                .foregroundStyle(metric.status.color)
                        }
                        .font(.subheadline.weight(.semibold))
                        ProgressView(
                            value: metric.weeklyValue ?? 0,
                            total: metric.weeklyTarget ?? 1
                        )
                        .tint(metric.status.color)
                        Text("\((metric.weeklyValue ?? 0).formatted(.number.precision(.fractionLength(0)))) of \((metric.weeklyTarget ?? 0).formatted(.number.precision(.fractionLength(0)))) \(metric.unit) this week")
                            .font(.caption)
                            .foregroundStyle(YoungerTheme.secondaryText)
                    }
                }
                Text("A rest day can still be on plan. Weekly pace matters more than forcing every target daily.")
                    .font(.caption)
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
            .padding(20)
            .youngerCard()
        }
    }

    @ViewBuilder
    private var notices: some View {
        if !model.healthNotices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Signals to watch", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(YoungerTheme.gold)
                ForEach(model.healthNotices) { notice in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: notice.icon).foregroundStyle(notice.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(notice.title).font(.subheadline.weight(.bold))
                            Text(notice.detail)
                                .font(.caption)
                                .foregroundStyle(YoungerTheme.secondaryText)
                        }
                    }
                }
            }
            .padding(20)
            .youngerCard()
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
            ForEach(model.visibleMetrics) { metric in
                NavigationLink {
                    MetricDetailView(metricID: metric.id)
                } label: {
                    MetricCard(metric: metric)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(YoungerTheme.secondaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.formattedValue)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                Text(metric.targetDescription)
                    .font(.caption)
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
            if metric.contributesToScore {
                ProgressView(value: metric.progress)
                    .tint(metric.status.color)
            } else {
                Divider().overlay(YoungerTheme.divider)
            }
            Label(metric.source.rawValue, systemImage: metric.source.icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(YoungerTheme.secondaryText)
            Text(metric.freshnessText)
                .font(.caption2)
                .foregroundStyle(YoungerTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .youngerCard()
    }
}

private struct MetricDetailView: View {
    @EnvironmentObject private var model: AppModel
    let metricID: String

    private var metric: DailyMetric? {
        model.metrics.first(where: { $0.id == metricID })
    }

    var body: some View {
        ZStack {
            YoungerBackground()
            if let metric {
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 20)

                        Image(systemName: metric.icon)
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(metric.status.color)

                        Text(metric.title.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(YoungerTheme.secondaryText)

                        Text(metric.formattedValue)
                            .font(.system(size: 92, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.45)
                            .lineLimit(1)

                        Text(metric.unit)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(YoungerTheme.secondaryText)

                        VStack(spacing: 12) {
                            Text(metric.status.label)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(metric.status.color)
                            Text(metric.targetDescription)
                                .font(.headline)
                            if metric.contributesToScore {
                                ProgressView(value: metric.progress)
                                    .tint(metric.status.color)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .youngerCard()

                        Text(metric.action)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)

                        VStack(spacing: 6) {
                            Label(metric.source.rawValue, systemImage: metric.source.icon)
                                .font(.subheadline.weight(.semibold))
                            Text(availabilityText(for: metric))
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(YoungerTheme.secondaryText)
                            Text(metric.freshnessText)
                                .font(.caption2)
                                .foregroundStyle(YoungerTheme.secondaryText)
                        }

                        historySection(metric)
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(metric?.title ?? "Metric")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: metricID) {
            while !Task.isCancelled {
                await model.refreshMetric(metricID)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    @ViewBuilder
    private func historySection(_ metric: DailyMetric) -> some View {
        let history = model.history(for: metric.id, days: 30)
        if history.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text("30-DAY TREND")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(YoungerTheme.secondaryText)
                Chart(history) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value(metric.title, point.value)
                    )
                    .foregroundStyle(metric.status.color)
                    PointMark(
                        x: .value("Day", point.date),
                        y: .value(metric.title, point.value)
                    )
                    .foregroundStyle(metric.status.color)
                }
                .frame(height: 130)
                Text(metric.weeklyPaceDescription ?? "Daily history builds each time Younger refreshes.")
                    .font(.caption)
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
            .padding(18)
            .youngerCard()
        } else {
            Text("Trend history will appear after Younger records this metric on multiple days.")
                .font(.caption)
                .foregroundStyle(YoungerTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func availabilityText(for metric: DailyMetric) -> String {
        if metric.value != nil {
            return "Refreshes every 15 seconds while this page is open."
        }
        if metric.source == .appleHealth && !model.healthConnected {
            return "Connect Apple Health to make this metric available."
        }
        if metric.source == .whoop && !model.whoopConnected {
            return "Connect WHOOP to make this metric available."
        }
        return "This metric is not currently supplied by the connected source."
    }
}

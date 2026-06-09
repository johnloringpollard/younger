import Charts
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Momentum")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                    Text("Consistency matters more than one perfect day.")
                        .foregroundStyle(YoungerTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(trendAverage)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text("recorded-day average")
                            .foregroundStyle(YoungerTheme.secondaryText)
                        Spacer()
                        Text("\(model.trend.count) days")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(YoungerTheme.secondaryText)
                    }

                    if model.trend.count >= 2 {
                        Chart(model.trend) { day in
                            AreaMark(
                                x: .value("Day", day.date),
                                y: .value("Score", day.score)
                            )
                            .foregroundStyle(
                                LinearGradient(colors: [YoungerTheme.mint.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom)
                            )
                            LineMark(
                                x: .value("Day", day.date),
                                y: .value("Score", day.score)
                            )
                            .foregroundStyle(YoungerTheme.mint)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                        .chartYScale(domain: 0...100)
                        .chartYAxis {
                            AxisMarks(values: [0, 50, 100]) {
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                                AxisValueLabel().foregroundStyle(YoungerTheme.secondaryText)
                            }
                        }
                        .frame(height: 220)
                    } else {
                        Text("Keep using Younger for a few days to build an honest trend.")
                            .font(.subheadline)
                            .foregroundStyle(YoungerTheme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(20)
                .youngerCard()

                Text("Metric trends")
                    .font(.title2.bold())

                ForEach(model.visibleMetrics) { metric in
                    let history = model.history(for: metric.id, days: 30)
                    InsightRow(
                        icon: metric.icon,
                        color: metric.status.color,
                        title: metric.title,
                        detail: trendDetail(metric: metric, history: history)
                    )
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var trendAverage: Int {
        Int((model.trend.map(\.score).reduce(0, +) / Double(max(model.trend.count, 1))).rounded())
    }

    private func trendDetail(metric: DailyMetric, history: [MetricHistoryPoint]) -> String {
        guard let first = history.first, let last = history.last, history.count >= 2 else {
            return "\(metric.freshnessText). More days are needed for a trend."
        }
        let change = last.value - first.value
        let direction = change > 0 ? "up" : change < 0 ? "down" : "steady"
        return "\(history.count)-day record is \(direction) by \(abs(change).formatted(.number.precision(.fractionLength(metric.decimals)))) \(metric.unit)."
    }
}

private struct InsightRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(Circle().fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(YoungerTheme.secondaryText)
            }
            Spacer()
        }
        .padding(18)
        .youngerCard()
    }
}

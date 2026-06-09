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
                        Text("\(Int(model.trend.map(\.score).reduce(0, +) / Double(max(model.trend.count, 1))))")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text("14-day average")
                            .foregroundStyle(YoungerTheme.secondaryText)
                        Spacer()
                        Label("+6", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(YoungerTheme.mint)
                    }

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
                    .chartYScale(domain: 40...100)
                    .chartYAxis {
                        AxisMarks(values: [50, 75, 100]) {
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                            AxisValueLabel().foregroundStyle(YoungerTheme.secondaryText)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 4)) {
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                                .foregroundStyle(YoungerTheme.secondaryText)
                        }
                    }
                    .frame(height: 220)
                }
                .padding(20)
                .youngerCard()

                Text("What’s moving you")
                    .font(.title2.bold())

                InsightRow(icon: "moon.fill", color: YoungerTheme.sky, title: "Sleep is your strongest lever", detail: "Your green days average 47 more minutes of sleep.")
                InsightRow(icon: "figure.walk", color: YoungerTheme.gold, title: "Afternoon movement dips", detail: "A walk after 3 PM would close your step gap most often.")
                InsightRow(icon: "heart.fill", color: YoungerTheme.coral, title: "Recovery is trending up", detail: "HRV and resting heart rate improved across the last 7 days.")
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
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

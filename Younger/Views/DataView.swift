import SwiftUI

struct DataView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""

    private var filtered: [HealthDataPoint] {
        guard !search.isEmpty else { return model.dataPoints }
        return model.dataPoints.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.category.localizedCaseInsensitiveContains(search)
        }
    }

    private var categories: [String] {
        Array(Set(filtered.map(\.category))).sorted()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your health data")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                    Text("\(model.dataPoints.count) signals available to Younger")
                        .foregroundStyle(YoungerTheme.secondaryText)
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(YoungerTheme.secondaryText)
                    TextField("Search metrics", text: $search)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(YoungerTheme.surface))

                ForEach(categories, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(YoungerTheme.secondaryText)
                            .tracking(1.2)

                        VStack(spacing: 0) {
                            ForEach(filtered.filter { $0.category == category }) { point in
                                HStack(spacing: 12) {
                                    Image(systemName: point.source.icon)
                                        .foregroundStyle(point.source == .whoop ? YoungerTheme.sky : YoungerTheme.coral)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(point.name).font(.subheadline.weight(.semibold))
                                        Text("\(point.source.rawValue) · \(point.updated)")
                                            .font(.caption)
                                            .foregroundStyle(YoungerTheme.secondaryText)
                                    }
                                    Spacer()
                                    Text(point.value)
                                        .font(.subheadline.weight(.bold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                if point.id != filtered.filter({ $0.category == category }).last?.id {
                                    Divider().overlay(YoungerTheme.divider).padding(.leading, 56)
                                }
                            }
                        }
                        .youngerCard()
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

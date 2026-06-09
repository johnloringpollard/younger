import SwiftUI

struct RootView: View {
    @State private var selection = 0

    var body: some View {
        ZStack {
            YoungerBackground()
            TabView(selection: $selection) {
                NavigationStack { TodayView() }
                    .tabItem { Label("Today", systemImage: "sparkles") }
                    .tag(0)

                NavigationStack { TrendsView() }
                    .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                    .tag(1)

                NavigationStack { DataView() }
                    .tabItem { Label("Data", systemImage: "square.stack.3d.up.fill") }
                    .tag(2)

                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                    .tag(3)
            }
            .tint(YoungerTheme.mint)
        }
    }
}

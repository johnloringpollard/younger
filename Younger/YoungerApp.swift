import SwiftUI

@main
struct YoungerApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .preferredColorScheme(.dark)
                .task {
                    await appModel.start()
                }
        }
    }
}

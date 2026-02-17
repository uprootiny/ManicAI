import SwiftUI

@main
struct ManicAIApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

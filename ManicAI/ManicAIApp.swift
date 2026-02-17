import SwiftUI

@main
struct ManicAIApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 1200, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

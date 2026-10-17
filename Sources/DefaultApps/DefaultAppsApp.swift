import SwiftUI

@main
struct DefaultAppsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 760, height: 560)
        .commands {
            DefaultAppsCommands()
        }
    }
}

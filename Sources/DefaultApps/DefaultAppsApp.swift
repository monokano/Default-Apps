import SwiftUI

@main
struct DefaultAppsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 980, height: 620)
        .commands {
            DefaultAppsCommands()
        }
    }
}

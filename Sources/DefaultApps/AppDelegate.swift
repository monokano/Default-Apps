import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        DispatchQueue.main.async {
            self.configureMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func configureMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }

        window.isRestorable = false
        window.minSize = NSSize(width: 600, height: 300)
        window.animationBehavior = .none

        // ウィンドウ位置を復元
        if let frame = PreferencesService.loadWindowFrame() {
            window.setFrame(frame, display: false)
            if let screen = window.screen ?? NSScreen.main {
                let constrained = window.constrainFrameRect(window.frame, to: screen)
                window.setFrame(constrained, display: false)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let frame = window?.frame else { return }
            PreferencesService.saveWindowFrame(frame)
        }
    }
}

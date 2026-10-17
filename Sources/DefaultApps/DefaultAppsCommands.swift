import SwiftUI

struct DefaultAppsCommands: Commands {
    @FocusedObject private var vm: ViewModel?
    @AppStorage(PreferencesService.showAllFileTypesKey) private var showAllFileTypes = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .undoRedo) {}

        // 表示メニュー: 更新
        CommandGroup(before: .sidebar) {
            Button(String(localized: "Refresh")) {
                vm?.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)

            Toggle(String(localized: "Show All File Types"), isOn: $showAllFileTypes)
                .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()
        }

        // ヘルプメニュー: 標準の「Default Apps ヘルプ」を GitHub のリリースページへのリンクに置き換える
        CommandGroup(replacing: .help) {
            Button(String(localized: "GitHub Releases")) {
                NSWorkspace.shared.open(Self.releasesURL)
            }
        }
    }

    // TODO: GitHub リポジトリは未作成（2026-10-18 時点で予定の URL）
    private static let releasesURL = URL(string: "https://github.com/monokano/Default-Apps/releases")!
}

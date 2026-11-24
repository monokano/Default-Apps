import SwiftUI

struct DefaultAppsCommands: Commands {
    @FocusedObject private var vm: ViewModel?

    var body: some Commands {
        // ファイルメニュー: 新規の代わりにアプリの追加・ダミーファイルの書き出し
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "Add App…")) {
                vm?.presentAddPanel()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(String(localized: "Export Dummy Files…")) {
                vm?.exportDummyFiles()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled((vm?.checkedCount ?? 0) == 0)
        }

        CommandGroup(replacing: .undoRedo) {}

        // 表示メニュー: 更新
        CommandGroup(before: .sidebar) {
            Button(String(localized: "Refresh")) {
                vm?.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)

            // 書類として開かない種類（プリセット・設定など。Role が None）も「その他」の区分に表示する
            Toggle(String(localized: "Show All File Types"), isOn: Binding(
                get: { vm?.showAllFileTypes ?? false },
                set: { vm?.showAllFileTypes = $0 }
            ))
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(vm == nil)

            Divider()
        }

        // ヘルプメニュー: 標準の「Default Apps ヘルプ」を GitHub のリリースページへのリンクに置き換える
        CommandGroup(replacing: .help) {
            Button(String(localized: "GitHub Releases")) {
                NSWorkspace.shared.open(Self.releasesURL)
            }
        }
    }

    private static let releasesURL = URL(string: "https://github.com/monokano/Default-Apps/releases")!
}

import AppKit

struct PreferencesService {

    private enum Key {
        static let windowFrame = "WindowFrame"
        static let appPaths = "AppPaths"
        static let checkedTypes = "CheckedTypes"
        static let selectedApp = "SelectedApp"
        /// v1 の「すべての対応ファイルを表示」（ShowAllFileTypes）とは意味が違うので別のキーにする
        static let showNonDocumentTypes = "ShowNonDocumentTypes"
    }

    // MARK: - Window frame

    static func saveWindowFrame(_ frame: NSRect) {
        let dict: [String: Double] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.size.width,
            "h": frame.size.height
        ]
        UserDefaults.standard.set(dict, forKey: Key.windowFrame)
    }

    static func loadWindowFrame() -> NSRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: Key.windowFrame),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double
        else { return nil }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - サイドバーのアプリ（.app のパス）

    static func saveAppPaths(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: Key.appPaths)
    }

    static func loadAppPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Key.appPaths) ?? []
    }

    // MARK: - チェックした書類の種類（アプリのパス → UTType 識別子）

    static func saveCheckedTypes(_ checked: [String: Set<String>]) {
        UserDefaults.standard.set(checked.mapValues { Array($0).sorted() }, forKey: Key.checkedTypes)
    }

    static func loadCheckedTypes() -> [String: Set<String>] {
        let dict = UserDefaults.standard.dictionary(forKey: Key.checkedTypes) as? [String: [String]] ?? [:]
        return dict.mapValues(Set.init)
    }

    // MARK: - サイドバーで最後に選んだアプリ（パス）

    static func saveSelectedApp(_ path: String?) {
        UserDefaults.standard.set(path, forKey: Key.selectedApp)
    }

    static func loadSelectedApp() -> String? {
        UserDefaults.standard.string(forKey: Key.selectedApp)
    }

    // MARK: - 表示メニュー「すべての対応ファイルを表示」（書類として開かない種類も表示する）

    static func saveShowAllFileTypes(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Key.showNonDocumentTypes)
    }

    static func loadShowAllFileTypes() -> Bool {
        UserDefaults.standard.bool(forKey: Key.showNonDocumentTypes)
    }
}

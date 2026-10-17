import AppKit

struct PreferencesService {

    /// 表示メニュー「すべての対応ファイルを表示」の状態（@AppStorage で直接読み書きする）
    static let showAllFileTypesKey = "ShowAllFileTypes"

    private enum Key {
        static let windowFrame = "WindowFrame"
        static let selectedFamily = "SelectedFamily"
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

    // MARK: - Selected app family（サイドバーで最後に選んだアプリ群の Bundle ID）

    static func saveSelectedFamily(_ bundleID: String?) {
        UserDefaults.standard.set(bundleID, forKey: Key.selectedFamily)
    }

    static func loadSelectedFamily() -> String? {
        UserDefaults.standard.string(forKey: Key.selectedFamily)
    }
}

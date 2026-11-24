import AppKit
import UniformTypeIdentifiers

/// サイドバーに追加されたアプリ 1つ分の情報
struct TargetApp: Identifiable {
    let appURL: URL
    let bundleID: String
    let name: String        // .app 名: "Adobe Photoshop 2024" など
    let version: String     // CFBundleShortVersionString
    /// ビルド番号（Adobe は AdobeBuildNumber、無ければ CFBundleVersion）。非正式版の表示の区別に使う
    var buildNumber: String? = nil
    let icon: NSImage
    let fileTypes: [FileTypeInfo]

    var id: URL { appURL }

    /// 設定の保存に使うキー（アプリのパス）
    var key: String { appURL.standardized.path }

    /// 表示用: "Adobe Photoshop 2024 (25.12.4)"
    var displayName: String { "\(name) (\(versionText))" }

    /// バージョンの表示。先頭3桁に揃える（"21.6.0.57" → "21.6.0"）
    /// - 非正式版は同じバージョンでもビルド番号で区別されるので " #84" を付ける
    ///   （4桁目以降があればそれを、無ければ AdobeBuildNumber などを使う。バージョンと同じなら付けない）
    var versionText: String {
        let parts = version.components(separatedBy: ".")
        let base = parts.prefix(3).joined(separator: ".")
        guard isPrerelease else { return base }
        if parts.count >= 4 {
            return base + " #" + parts.dropFirst(3).joined(separator: ".")
        }
        guard let build = buildNumber, !build.isEmpty, build != version else { return base }
        return "\(base) #\(build)"
    }

    /// ベータ版・プレリリース版などの非正式版か
    /// （Bundle ID に Beta などの印がある、または名前かバージョン文字列に beta／preview などの語を含む）
    /// 名前がその語だけのとき（macOS の「プレビュー」= "Preview"）は、アプリの名前なので非正式版とみなさない
    var isPrerelease: Bool {
        if AppScanner.hasPrereleaseSuffix(bundleID) { return true }
        let pattern = #"\b(alpha|beta|pre-?release|preview|seed|nightly|canary|dev|rc\d*)\b|\d(a|b|rc)\d"#
        return [name, version].contains {
            guard let range = $0.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return false }
            return range != $0.startIndex..<$0.endIndex
        }
    }
}

/// アプリが開ける書類の種類（UTType 1つ分）
struct FileTypeInfo: Identifiable {
    let type: UTType
    let extensions: [String]
    let description: String
    /// 書類として開く種類か（CFBundleTypeRole が Editor／Viewer）。
    /// false はプリセット・設定・プラグインなど、書類としては開かない種類（Role が None）
    var isDocument: Bool = true

    var id: String { type.identifier }

    /// 一覧表示用: ".psd, .pdd"
    var extensionsText: String {
        extensions.isEmpty ? type.identifier : extensions.map { "." + $0 }.joined(separator: ", ")
    }

    /// ダミーファイルに使う拡張子（先頭のもの）。拡張子が無い種類はダミーファイルを作れない
    var dummyExtension: String? { extensions.first }

    /// 重複の判定用（小文字の拡張子）
    var lowercasedExtensions: Set<String> { Set(extensions.map { $0.lowercased() }) }
}

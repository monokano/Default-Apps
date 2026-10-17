import AppKit
import UniformTypeIdentifiers

/// 同じ Bundle ID を持つアプリ群（複数バージョンがインストールされているもの）。
/// "com.adobe.illustratorBeta" のように Beta などの印だけが違う Bundle ID も同じ群に入れる
struct AppFamily: Identifiable {
    let bundleID: String    // 正式版の Bundle ID（ID・設定保存用）
    let name: String        // サイドバー表示用: "Adobe Photoshop" など
    let icon: NSImage       // 正式版の最新のアイコン（正式版が無ければ最新版）
    let versions: [AppVersion]  // 古い順

    var id: String { bundleID }
}

/// インストールされているアプリ 1つ分の情報
struct AppVersion: Identifiable {
    let appURL: URL
    let bundleID: String
    let name: String        // .app 名: "Adobe Photoshop 2024" など
    let version: String     // CFBundleShortVersionString
    /// ビルド番号（Adobe は AdobeBuildNumber、無ければ CFBundleVersion）。非正式版の表示の区別に使う
    var buildNumber: String? = nil
    let icon: NSImage
    let fileTypes: [FileTypeInfo]
    /// 同じ名前・同じバージョンのコピーが他にもあるとき、区別用に表示する場所（"~/Applications" など）
    var locationNote: String? = nil

    var id: URL { appURL }

    /// ポップアップ表示用: "Adobe Photoshop 2024 (25.12.4)"、コピーがあれば " — ~/Applications" を付ける
    /// バージョンは3桁に揃え、非正式版はビルド番号も付ける: "Adobe Illustrator 2027 (Beta) (31.0.0 #64)"
    var displayName: String {
        let base = "\(name) (\(versionText))"
        guard let locationNote else { return base }
        return "\(base) — \(locationNote)"
    }

    /// バージョンの表示。先頭3桁に揃える（"21.6.0.57" → "21.6.0"）
    /// - 非正式版は同じバージョンでもビルド番号で区別されるので " #84" を付ける
    ///   （4桁目以降があればそれを、無ければ AdobeBuildNumber などを使う。バージョンと同じなら付けない）
    private var versionText: String {
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
    var isPrerelease: Bool {
        if AppScanner.hasPrereleaseSuffix(bundleID) { return true }
        let pattern = #"\b(alpha|beta|pre-?release|preview|seed|nightly|canary|dev|rc\d*)\b|\d(a|b|rc)\d"#
        return [name, version].contains {
            $0.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// バージョン比較用の数値（"25.12.4" → 25_012_004）
    var versionValue: Int {
        let parts = version.components(separatedBy: ".").prefix(3).map { Int($0) ?? 0 }
        return parts.enumerated().reduce(0) { sum, item in
            sum + item.element * [1_000_000, 1_000, 1][item.offset]
        }
    }
}

/// アプリが開ける書類の種類（UTType 1つ分）
struct FileTypeInfo: Identifiable {
    let type: UTType
    let extensions: [String]
    let description: String

    var id: String { type.identifier }

    /// 一覧表示用: ".psd, .pdd"
    var extensionsText: String {
        extensions.isEmpty ? type.identifier : extensions.map { "." + $0 }.joined(separator: ", ")
    }
}

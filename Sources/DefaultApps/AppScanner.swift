import AppKit
import UniformTypeIdentifiers

struct AppScanner {

    /// Bundle ID 末尾の非正式版の印（"com.adobe.illustratorBeta" の "Beta" など）
    private static let prereleaseSuffixPattern = #"[.\-_]?(beta|prerelease|pre-release|preview|alpha|nightly|canary|seed)$"#

    /// Bundle ID に非正式版の印が付いているか（"com.adobe.illustratorBeta" など）。
    /// 最後の要素そのものが印の語のとき（"com.apple.Preview"）は、アプリの名前なので印とみなさない
    static func hasPrereleaseSuffix(_ bundleID: String) -> Bool {
        guard let last = bundleID.split(separator: ".").last.map(String.init),
              let range = last.range(of: prereleaseSuffixPattern, options: [.regularExpression, .caseInsensitive])
        else { return false }
        return range.lowerBound != last.startIndex
    }

    /// .app を読み込む。アプリでない・Info.plist が読めないときは nil
    static func loadApp(at url: URL) -> TargetApp? {
        guard let plist = readInfoPlist(bundle: url),
              let bundleID = plist["CFBundleIdentifier"] as? String
        else { return nil }

        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
            ?? ""
        let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []

        return TargetApp(
            appURL: url,
            bundleID: bundleID,
            name: displayName(of: url),
            version: version,
            buildNumber: (plist["AdobeBuildNumber"] as? String) ?? (plist["CFBundleVersion"] as? String),
            icon: bundleIcon(appURL: url, info: plist) ?? NSWorkspace.shared.icon(forFile: url.path),
            fileTypes: makeFileTypes(docTypes)
        )
    }

    /// 書類の種類に現在関連付けられているアプリ
    static func currentHandler(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    /// 関連付け先の表示名。同じ名前の別バージョンと区別できるようバージョンも付ける: "Adobe Photoshop 2024 (25.12.4)"
    static func handlerDisplayName(_ url: URL) -> String {
        loadApp(at: url)?.displayName
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Private

    /// 総称の種類。そのアプリと関係ないファイルまで含んでしまうので扱わない
    private static let genericTypeIDs: Set<String> = [
        "public.item", "public.data", "public.content", "public.composite-content",
        "public.directory", "public.folder",
    ]

    private static func readInfoPlist(bundle: URL) -> [String: Any]? {
        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// アプリのアイコンを Info.plist の CFBundleIconFile の .icns から直接読む。
    /// macOS 26 以降の NSWorkspace.icon(forFile:) は、Icon Composer 形式のアイコンを持たないアプリ
    /// （Adobe 製品など）のアイコンを縮めてグレーの角丸の枠に入れて返すため。
    /// 読めなければ nil（呼び出し側で従来の API に戻す）。
    /// 詳細は App-共有資料/アプリアイコンのグレー枠_macOS26以降.md
    private static func bundleIcon(appURL: URL, info: [String: Any]) -> NSImage? {
        guard let name = info["CFBundleIconFile"] as? String, !name.isEmpty else { return nil }
        let file = name.hasSuffix(".icns") ? name : name + ".icns"
        return NSImage(contentsOf: appURL.appendingPathComponent("Contents/Resources/\(file)"))
    }

    /// 表示名。.app 名を使うが、入っているフォルダ名が .app 名で始まるならフォルダ名を使う
    /// （"Adobe Illustrator (Beta)/Adobe Illustrator.app" → "Adobe Illustrator (Beta)"、
    ///   "Adobe Illustrator 2025/Adobe Illustrator.app" → "Adobe Illustrator 2025"）
    private static func displayName(of bundle: URL) -> String {
        let appName = FileManager.default.displayName(atPath: bundle.path)
            .replacingOccurrences(of: ".app", with: "")
        let folderName = FileManager.default.displayName(atPath: bundle.deletingLastPathComponent().path)
        return folderName.count > appName.count && folderName.hasPrefix(appName) ? folderName : appName
    }

    /// CFBundleDocumentTypes から UTType の一覧を作る（重複は除き、拡張子順）
    /// - LSItemContentTypes があればそれを使い、無ければ拡張子から UTType を引く
    /// - 拡張子 "*"（任意のファイル）と、public.data などの総称の種類は対象外
    /// - 役割（CFBundleTypeRole）が None の宣言は「書類としては開かない種類」とする。
    ///   同じ種類に複数の宣言があるときは、書類として開く宣言（Editor／Viewer）が1つでもあれば書類とみなす
    private static func makeFileTypes(_ docTypes: [[String: Any]]) -> [FileTypeInfo] {
        var index: [String: Int] = [:]
        var result: [FileTypeInfo] = []

        func add(_ type: UTType, fallbackExtension: String?, isDocument: Bool) {
            guard !genericTypeIDs.contains(type.identifier) else { return }
            if let i = index[type.identifier] {
                if isDocument && !result[i].isDocument { result[i].isDocument = true }
                return
            }
            var exts = type.tags[.filenameExtension] ?? []
            if exts.isEmpty, let ext = fallbackExtension { exts = [ext] }
            let desc = type.localizedDescription ?? (exts.first?.uppercased() ?? type.identifier)
            index[type.identifier] = result.count
            result.append(FileTypeInfo(type: type, extensions: exts, description: desc, isDocument: isDocument))
        }

        for docType in docTypes {
            let utis = docType["LSItemContentTypes"] as? [String] ?? []
            let exts = (docType["CFBundleTypeExtensions"] as? [String] ?? []).filter { $0 != "*" }
            // 役割の指定が無いときは書類として扱う（Editor 扱い）
            let isDocument = (docType["CFBundleTypeRole"] as? String)?.lowercased() != "none"

            if !utis.isEmpty {
                for uti in utis {
                    if let type = UTType(uti) { add(type, fallbackExtension: exts.first, isDocument: isDocument) }
                }
            } else {
                for ext in exts {
                    if let type = UTType(filenameExtension: ext) { add(type, fallbackExtension: ext, isDocument: isDocument) }
                }
            }
        }

        return result.sorted {
            ($0.extensions.first ?? $0.id).localizedCaseInsensitiveCompare($1.extensions.first ?? $1.id) == .orderedAscending
        }
    }
}

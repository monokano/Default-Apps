import AppKit
import UniformTypeIdentifiers

struct AppScanner {

    /// 走査するフォルダ。ゴミ箱・マウント中の DMG・Time Machine・外付けボリュームはここに含まれないので対象外になる
    private static var searchRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    /// サブフォルダを何階層まで見るか（/Applications/Adobe Photoshop 2024/Adobe Photoshop 2024.app が 2）
    private static let maxDepth = 3

    /// Bundle ID 末尾の非正式版の印（"com.adobe.illustratorBeta" の "Beta" など）
    private static let prereleaseSuffixPattern = #"[.\-_]?(beta|prerelease|pre-release|preview|alpha|nightly|canary|seed)$"#

    /// アプリ群をまとめるキー。非正式版の印を除いた小文字の Bundle ID
    /// （"com.adobe.illustratorBeta" → "com.adobe.illustrator"）
    static func familyKey(_ bundleID: String) -> String {
        bundleID.lowercased()
            .replacingOccurrences(of: prereleaseSuffixPattern, with: "", options: .regularExpression)
    }

    /// Bundle ID に非正式版の印が付いているか
    static func hasPrereleaseSuffix(_ bundleID: String) -> Bool {
        familyKey(bundleID) != bundleID.lowercased()
    }

    /// 同じ Bundle ID（Beta などの印は除いて比べる）のアプリが2つ以上あるものを、アプリ群として名前順に返す
    /// - 書類の種類を1つも開けないアプリ群（アンインストーラーなど）は除く
    static func scanAll() -> [AppFamily] {
        var candidates: [(url: URL, plist: [String: Any], bundleID: String)] = []
        var seenPaths = Set<String>()

        for root in searchRoots {
            for url in findApps(in: root) {
                let path = url.resolvingSymlinksInPath().standardized.path
                guard seenPaths.insert(path).inserted,
                      let plist = readInfoPlist(bundle: url),
                      let bundleID = plist["CFBundleIdentifier"] as? String,
                      !isBackgroundApp(plist)
                else { continue }
                candidates.append((url, plist, bundleID))
            }
        }

        let groups = Dictionary(grouping: candidates, by: { familyKey($0.bundleID) })

        var families: [AppFamily] = []
        for (_, members) in groups where members.count >= 2 {
            var versions = members.compactMap { makeVersion(bundle: $0.url, plist: $0.plist, bundleID: $0.bundleID) }
            guard versions.count >= 2, versions.contains(where: { !$0.fileTypes.isEmpty }) else { continue }

            addLocationNotes(&versions)
            versions.sort {
                $0.versionValue != $1.versionValue
                    ? $0.versionValue < $1.versionValue
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

            families.append(AppFamily(
                // アプリ群の ID は正式版の Bundle ID（印の付いていない一番短いもの）
                bundleID: versions.map(\.bundleID).min { $0.count < $1.count }!,
                name: familyName(versions.map(\.name)),
                // サイドバーのアイコンは正式版の最新を使う（ベータ版はアイコンの見た目が違うことが多い）
                icon: (versions.last { !$0.isPrerelease } ?? versions.last!).icon,
                versions: versions
            ))
        }

        return families.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 総称の種類。関連付けると、そのアプリと関係ないファイルまで開くようになるので扱わない
    private static let genericTypeIDs: Set<String> = [
        "public.item", "public.data", "public.content", "public.composite-content",
        "public.directory", "public.folder",
    ]

    /// 書類の種類に現在関連付けられているアプリ
    static func currentHandler(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    // MARK: - Private

    /// フォルダ内の .app を探す（.app の中と、隠しファイル・シンボリックリンクは見ない）
    private static func findApps(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            guard values?.isDirectory == true else { continue }

            if url.pathExtension.lowercased() == "app" {
                result.append(url)
            } else if enumerator.level >= maxDepth {
                enumerator.skipDescendants()
            }
        }
        return result
    }

    private static func readInfoPlist(bundle: URL) -> [String: Any]? {
        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// メニューバー常駐・バックグラウンド専用のアプリ（ヘルパー類）
    private static func isBackgroundApp(_ plist: [String: Any]) -> Bool {
        func flag(_ key: String) -> Bool {
            if let b = plist[key] as? Bool { return b }
            if let s = plist[key] as? String { return s == "1" || s.lowercased() == "yes" || s.lowercased() == "true" }
            if let n = plist[key] as? NSNumber { return n.boolValue }
            return false
        }
        return flag("LSUIElement") || flag("LSBackgroundOnly")
    }

    private static func makeVersion(bundle: URL, plist: [String: Any], bundleID: String) -> AppVersion? {
        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
            ?? ""
        guard !version.isEmpty else { return nil }

        let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []

        return AppVersion(
            appURL: bundle,
            bundleID: bundleID,
            name: displayName(of: bundle),
            version: version,
            buildNumber: (plist["AdobeBuildNumber"] as? String) ?? (plist["CFBundleVersion"] as? String),
            icon: NSWorkspace.shared.icon(forFile: bundle.path),
            fileTypes: makeFileTypes(docTypes)
        )
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

    /// 同じ名前・同じバージョンのコピーには、置き場所を表示用に付ける
    private static func addLocationNotes(_ versions: inout [AppVersion]) {
        let keyCounts = Dictionary(grouping: versions.indices, by: { "\(versions[$0].name)\t\(versions[$0].version)" })
        for (_, indices) in keyCounts where indices.count >= 2 {
            for i in indices {
                let folder = versions[i].appURL.deletingLastPathComponent().path
                versions[i].locationNote = (folder as NSString).abbreviatingWithTildeInPath
            }
        }
    }

    /// アプリ群の表示名。各バージョンの名前に共通する先頭の単語を使う
    /// （"Adobe Photoshop 2024" と "Adobe Photoshop 2025" → "Adobe Photoshop"）。
    /// 共通部分が無ければ一番短い名前（"Xcode" と "Xcode-beta" → "Xcode"）。
    private static func familyName(_ names: [String]) -> String {
        let words = names.map { $0.split(separator: " ").map(String.init) }
        var common = words.first ?? []
        for w in words.dropFirst() {
            common = Array(zip(common, w).prefix { $0 == $1 }.map(\.0))
        }
        if !common.isEmpty, names.contains(where: { $0 != names[0] }) {
            return common.joined(separator: " ")
        }
        return names.min { $0.count < $1.count } ?? ""
    }

    /// CFBundleDocumentTypes から UTType の一覧を作る（重複は除き、拡張子順）
    /// - LSItemContentTypes があればそれを使い、無ければ拡張子から UTType を引く
    /// - 拡張子 "*"（任意のファイル）と、public.data などの総称の種類は対象外
    private static func makeFileTypes(_ docTypes: [[String: Any]]) -> [FileTypeInfo] {
        var seen = Set<String>()
        var result: [FileTypeInfo] = []

        func add(_ type: UTType, fallbackExtension: String?) {
            guard !genericTypeIDs.contains(type.identifier),
                  seen.insert(type.identifier).inserted
            else { return }
            var exts = type.tags[.filenameExtension] ?? []
            if exts.isEmpty, let ext = fallbackExtension { exts = [ext] }
            let desc = type.localizedDescription ?? (exts.first?.uppercased() ?? type.identifier)
            result.append(FileTypeInfo(type: type, extensions: exts, description: desc))
        }

        for docType in docTypes {
            let utis = docType["LSItemContentTypes"] as? [String] ?? []
            let exts = (docType["CFBundleTypeExtensions"] as? [String] ?? []).filter { $0 != "*" }

            if !utis.isEmpty {
                for uti in utis {
                    if let type = UTType(uti) { add(type, fallbackExtension: exts.first) }
                }
            } else {
                for ext in exts {
                    if let type = UTType(filenameExtension: ext) { add(type, fallbackExtension: ext) }
                }
            }
        }

        return result.sorted {
            ($0.extensions.first ?? $0.id).localizedCaseInsensitiveCompare($1.extensions.first ?? $1.id) == .orderedAscending
        }
    }
}

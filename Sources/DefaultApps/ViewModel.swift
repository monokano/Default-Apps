@preconcurrency import AppKit
import UniformTypeIdentifiers

@MainActor
final class ViewModel: ObservableObject {
    @Published var families: [AppFamily] = []
    /// サイドバーで選択中のアプリ群（Bundle ID）
    @Published var selectedFamilyID: String? = nil {
        didSet {
            guard selectedFamilyID != oldValue else { return }
            PreferencesService.saveSelectedFamily(selectedFamilyID)
            selectDefaultVersion()
        }
    }
    /// ポップアップで選択中のバージョン（アプリの URL）
    @Published var selectedURL: URL? = nil
    /// UTType 識別子 → 現在関連付けられているアプリ
    @Published var currentHandlers: [String: URL] = [:]
    @Published var isAssociating = false

    /// 関連付け先アプリの URL → Bundle ID（Bundle の読み込みを繰り返さないため）
    private var bundleIDCache: [URL: String] = [:]

    var selectedFamily: AppFamily? {
        families.first { $0.id == selectedFamilyID }
    }

    var selected: AppVersion? {
        selectedFamily?.versions.first { $0.appURL == selectedURL }
    }

    /// 一覧・関連付けの対象。選択中バージョンの対応形式のうち、
    /// 現在いずれかのバージョン（同じ Bundle ID。Beta などの印の違いは同じとみなす）に関連付けられているものだけに限る
    /// （他アプリに関連付けられている形式を奪わないため）。
    var fileTypes: [FileTypeInfo] {
        guard let family = selectedFamily, let selected else { return [] }
        return selected.fileTypes.filter { isHandledByFamily($0, family) }
    }

    /// 「すべての対応ファイルを表示」で下に出す、選択中バージョンの対応形式のうち fileTypes に入らないもの
    /// （他のアプリに関連付けられているもの・関連付け先が無いもの）。関連付けの対象にはしない
    var otherFileTypes: [FileTypeInfo] {
        guard let family = selectedFamily, let selected else { return [] }
        return selected.fileTypes.filter { !isHandledByFamily($0, family) }
    }

    init() {
        refresh()
    }

    // MARK: - Actions

    func refresh() {
        families = AppScanner.scanAll()
        refreshHandlers()

        // 選択が無効なら、前回のアプリ群 → 先頭 の順で選ぶ
        if selectedFamily == nil {
            let saved = PreferencesService.loadSelectedFamily()
            selectedFamilyID = families.first { $0.id == saved }?.id ?? families.first?.id
        }
        if selected == nil {
            selectDefaultVersion()
        }
    }

    func refreshHandlers() {
        var handlers: [String: URL] = [:]
        for family in families {
            for version in family.versions {
                for ft in version.fileTypes where handlers[ft.id] == nil {
                    handlers[ft.id] = AppScanner.currentHandler(for: ft.type)
                }
            }
        }
        currentHandlers = handlers
        bundleIDCache = [:]
    }

    /// 現在の関連付け先の表示名（同じアプリ群のバージョンなら .app 名、それ以外はアプリ名）
    func handlerName(for fileType: FileTypeInfo) -> String {
        guard let url = currentHandlers[fileType.id] else { return "—" }
        if let version = selectedFamily?.versions.first(where: { $0.appURL.standardized == url.standardized }) {
            return version.name
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    func isAssociatedWithSelected(_ fileType: FileTypeInfo) -> Bool {
        guard let selected, let url = currentHandlers[fileType.id] else { return false }
        return url.standardized == selected.appURL.standardized
    }

    /// 選択中のバージョンに対象の書類の種類（fileTypes）を関連付け、一覧の関連付け先を更新する（アプリは終了しない）。
    /// 対象のアプリは全バージョンが同じ Bundle ID を共有するため、
    /// Bundle ID 指定の LSSetDefaultRoleHandlerForContentType ではバージョンを区別できない。
    /// アプリの URL で指定できる NSWorkspace.setDefaultApplication(at:toOpen:) を使う。
    func associate() {
        guard let version = selected, !isAssociating else { return }
        let targets = fileTypes
        isAssociating = true

        Task {
            var failures: [String] = []
            for ft in targets {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: version.appURL, toOpen: ft.type)
                } catch {
                    failures.append("\(ft.extensionsText) — \(error.localizedDescription)")
                }
            }
            isAssociating = false

            refreshHandlers()
            if !failures.isEmpty {
                showFailureAlert(failures)
            }
        }
    }

    // MARK: - Private

    /// アプリ群を選んだときの初期バージョン：
    /// 現在いちばん多くの形式が関連付けられているバージョン → 無ければ最新版
    private func selectDefaultVersion() {
        guard let family = selectedFamily else {
            selectedURL = nil
            return
        }
        var counts: [URL: Int] = [:]
        let typeIDs = Set(family.versions.flatMap { $0.fileTypes.map(\.id) })
        for id in typeIDs {
            if let url = currentHandlers[id]?.standardized { counts[url, default: 0] += 1 }
        }
        let best = family.versions
            .map { ($0, counts[$0.appURL.standardized] ?? 0) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
        selectedURL = (best ?? family.versions.last)?.appURL
    }

    private func isHandledByFamily(_ fileType: FileTypeInfo, _ family: AppFamily) -> Bool {
        guard let url = currentHandlers[fileType.id] else { return false }
        guard let id = bundleID(of: url) else { return false }
        return AppScanner.familyKey(id) == AppScanner.familyKey(family.bundleID)
    }

    private func bundleID(of url: URL) -> String? {
        if let cached = bundleIDCache[url] { return cached }
        let id = Bundle(url: url)?.bundleIdentifier
        bundleIDCache[url] = id
        return id
    }

    private func showFailureAlert(_ failures: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Some file types could not be associated.")
        alert.informativeText = failures.joined(separator: "\n")
        alert.runModal()
    }
}

@preconcurrency import AppKit
import UniformTypeIdentifiers

/// 他のアプリでも同じ拡張子にチェックが入っているもの（ウインドウ下部に表示する）
struct DuplicateNotice: Identifiable {
    let extensionsText: String   // 重なっている拡張子: ".psd"
    let appNames: [String]       // 同じ拡張子にチェックが入っている他のアプリ

    var id: String { extensionsText }
}

/// 一覧（テーブル）の1行。列の並べ替えに使う値を持つ
struct FileTypeRow: Identifiable {
    let fileType: FileTypeInfo
    let extensionsText: String   // 拡張子の列: ".psd, .pdd"
    let kind: String             // 種類の列
    let handlerName: String      // 関連付けアプリの列（名前＋バージョン。無ければ "—"）

    var id: String { fileType.id }
}

/// 一覧の区分：チェック済み／書類／その他（プリセット・設定など）
struct FileTypeSection: Identifiable {
    enum Kind: String { case checked, documents, others }
    let kind: Kind
    let rows: [FileTypeRow]

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .checked: String(localized: "Checked", comment: "File list section header: file types that were checked at the last refresh")
        case .documents: String(localized: "Documents", comment: "File list section header: file types the app opens as documents (role Editor/Viewer)")
        case .others: String(localized: "Other File Types (Presets, Settings, etc.)", comment: "File list section header: file types the app declares but does not open as documents (role None)")
        }
    }
}

@MainActor
final class ViewModel: ObservableObject {
    /// サイドバーのアプリ（名前・バージョン順）
    @Published private(set) var apps: [TargetApp] = []
    @Published var selectedAppID: URL? = nil {
        didSet {
            guard selectedAppID != oldValue else { return }
            // ここでは @Published を書き換えない。サイドバーの選択はビューの更新中に届くので、
            // 書き換えると「Publishing changes from within view updates」になる。
            // 「チェック済み」の区分とステータスの表示は、アプリのキー付きで持って読むときに判定する
            PreferencesService.saveSelectedApp(selectedApp?.key)
        }
    }
    /// アプリのパス → チェックした書類の種類（UTType 識別子）
    @Published private(set) var checked: [String: Set<String>] = [:]
    /// UTType 識別子 → 現在関連付けられているアプリ
    @Published private(set) var currentHandlers: [String: URL] = [:]
    /// 「チェック済み」の区分に入れる種類（UTType 識別子）と、それがどのアプリのものか（アプリのキー）。
    /// 更新ボタン・アプリを選んで最初にチェックを切り替えたとき、その時点でチェックの入っていたものに決める。
    /// チェックを切り替えた瞬間に行が動かないよう、切り替えでは変えない
    @Published private var pinned: (appKey: String, ids: Set<String>)? = nil
    /// 列見出しのクリックで決まる並び順（区分それぞれの中で並べる）
    @Published var sortOrder: [KeyPathComparator<FileTypeRow>] = [
        KeyPathComparator(\FileTypeRow.extensionsText, comparator: .localizedStandard)
    ]
    /// 拡張子の検索（前方一致。先頭の "." は無視）
    @Published var searchText = ""
    /// 表示メニュー「すべての対応ファイルを表示」。オフのときは書類として開かない種類（Role が None）を隠す
    @Published var showAllFileTypes = PreferencesService.loadShowAllFileTypes() {
        didSet {
            guard showAllFileTypes != oldValue else { return }
            PreferencesService.saveShowAllFileTypes(showAllFileTypes)
        }
    }
    /// 書き出しの結果などをウインドウ下部に出す（どのアプリで書き出したか付き。別のアプリを選ぶと出さない）
    @Published private var status: (appKey: String, text: String)? = nil

    var statusMessage: String? {
        guard let status, status.appKey == selectedApp?.key else { return nil }
        return status.text
    }

    /// 関連付け先アプリの URL → 表示名（Info.plist の読み込みを繰り返さないため）
    private var handlerNameCache: [URL: String] = [:]

    var selectedApp: TargetApp? {
        apps.first { $0.id == selectedAppID }
    }

    /// 選択中のアプリの対応ファイル一覧のうち、表示するもの（検索で絞る前・並べ替え前）。
    /// 「すべての対応ファイルを表示」がオフなら、書類として開かない種類を除く
    var fileTypes: [FileTypeInfo] {
        guard let app = selectedApp else { return [] }
        return visibleFileTypes(of: app)
    }

    /// 一覧の区分：検索で絞り、チェック済み（pinnedTypeIDs）／書類／その他に分けて、それぞれを sortOrder で並べる。
    /// 中身の無い区分は入れない
    var sections: [FileTypeSection] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
            .drop { $0 == "." }.lowercased()
        let all = fileTypes
            .filter { query.isEmpty || $0.lowercasedExtensions.contains { $0.hasPrefix(query) } }
            .map { FileTypeRow(fileType: $0, extensionsText: $0.extensionsText,
                               kind: $0.description, handlerName: handlerName(for: $0)) }
        let pinnedIDs = pinnedTypeIDs
        let checked = all.filter { pinnedIDs.contains($0.id) }
        let rest = all.filter { !pinnedIDs.contains($0.id) }
        return [
            FileTypeSection(kind: .checked, rows: checked.sorted(using: sortOrder)),
            FileTypeSection(kind: .documents, rows: rest.filter { $0.fileType.isDocument }.sorted(using: sortOrder)),
            FileTypeSection(kind: .others, rows: rest.filter { !$0.fileType.isDocument }.sorted(using: sortOrder)),
        ].filter { !$0.rows.isEmpty }
    }

    /// 表示している種類のうちチェックの入っているもの（隠れている種類のチェックは数えない・書き出さない）
    var checkedCount: Int {
        guard let app = selectedApp else { return 0 }
        return fileTypes.filter { isChecked($0, in: app) }.count
    }

    init() {
        checked = PreferencesService.loadCheckedTypes()
        let urls = PreferencesService.loadAppPaths().map { URL(fileURLWithPath: $0) }
        // サイドバーの並び順は保存した順（ユーザーがドラッグで並べ替えられる）
        apps = urls.compactMap(AppScanner.loadApp(at:))
        // 見つからなくなったアプリ（削除・移動）はサイドバーから外す
        if apps.count != urls.count { saveApps() }
        refreshHandlers()

        let saved = PreferencesService.loadSelectedApp()
        selectedAppID = (apps.first { $0.key == saved } ?? apps.first)?.id
    }

    // MARK: - Sidebar

    /// .app を選ぶダイアログを出して、サイドバーに追加する
    func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Add", comment: "Open panel button: adds the chosen apps to the sidebar")
        guard panel.runModal() == .OK else { return }
        addApps(panel.urls)
    }

    /// サイドバーに追加する（追加済みのアプリは選択するだけ）。最後に追加・指定したアプリを選択する
    /// - index: 追加する位置（サイドバーの行の間へドロップしたとき）。nil なら末尾
    func addApps(_ urls: [URL], at index: Int? = nil) {
        var lastID: URL?
        var insertAt = min(index ?? apps.count, apps.count)
        for url in urls where url.pathExtension.lowercased() == "app" {
            let path = url.standardized.path
            if let existing = apps.first(where: { $0.key == path }) {
                lastID = existing.id
            } else if let app = AppScanner.loadApp(at: url.standardized) {
                apps.insert(app, at: insertAt)
                insertAt += 1
                lastID = app.id
            }
        }
        saveApps()
        refreshHandlers()
        if let lastID { selectedAppID = lastID }
    }

    /// サイドバーの行をドラッグで並べ替える
    func moveApps(fromOffsets source: IndexSet, toOffset destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        saveApps()
    }

    func removeApp(_ id: URL?) {
        guard let id, let index = apps.firstIndex(where: { $0.id == id }) else { return }
        let removed = apps.remove(at: index)
        checked[removed.key] = nil
        saveApps()
        PreferencesService.saveCheckedTypes(checked)
        if selectedAppID == id {
            selectedAppID = apps.isEmpty ? nil : apps[min(index, apps.count - 1)].id
        }
    }

    // MARK: - List

    /// 更新ボタン: アプリの対応ファイル・関連付け先を読み直し、チェックの入ったものを上にまとめる
    func refresh() {
        apps = apps.compactMap { AppScanner.loadApp(at: $0.appURL) }
        saveApps()
        refreshHandlers()
        if selectedApp == nil { selectedAppID = apps.first?.id }
        status = nil
        pinCheckedTypes()
    }

    func isChecked(_ fileType: FileTypeInfo) -> Bool {
        guard let app = selectedApp else { return false }
        return isChecked(fileType, in: app)
    }

    func setChecked(_ fileType: FileTypeInfo, _ on: Bool) {
        guard let app = selectedApp else { return }
        // アプリを選んでから最初の切り替えなら、切り替える前のチェックで「チェック済み」の区分を決めておく（行が動かないように）
        if pinned?.appKey != app.key { pinCheckedTypes() }
        var set = checked[app.key] ?? []
        if on { set.insert(fileType.id) } else { set.remove(fileType.id) }
        checked[app.key] = set.isEmpty ? nil : set
        PreferencesService.saveCheckedTypes(checked)
    }

    /// 現在の関連付け先の表示名
    func handlerName(for fileType: FileTypeInfo) -> String {
        guard let url = currentHandlers[fileType.id] else { return "—" }
        if let cached = handlerNameCache[url] { return cached }
        let name = AppScanner.handlerDisplayName(url)
        handlerNameCache[url] = name
        return name
    }

    /// 選択中のアプリでチェックした拡張子のうち、サイドバーの他のアプリでもチェックが入っているもの
    var duplicateNotices: [DuplicateNotice] {
        guard let app = selectedApp else { return [] }
        let others = apps.filter { $0.id != app.id }
        return fileTypes.filter { isChecked($0, in: app) }.compactMap { ft in
            var shared = Set<String>()
            var names: [String] = []
            for other in others {
                let exts = visibleFileTypes(of: other)
                    .filter { isChecked($0, in: other) }
                    .reduce(into: Set<String>()) { $0.formUnion($1.lowercasedExtensions) }
                    .intersection(ft.lowercasedExtensions)
                if !exts.isEmpty {
                    shared.formUnion(exts)
                    // 追加したアプリはバージョンに意味が無い（拡張子を取り出すためだけ）ので名前だけ
                    names.append(other.name)
                }
            }
            guard !names.isEmpty else { return nil }
            let text = shared.sorted().map { "." + $0 }.joined(separator: ", ")
            return DuplicateNotice(extensionsText: text, appNames: names)
        }
    }

    // MARK: - Export

    /// チェックした書類の種類のダミーファイル（空ファイル）を、選んだフォルダに書き出す（複数なら新しいフォルダにまとめる）。
    /// ファイル名は「ダミー.psd」のように、どのアプリ用か誤解されない名前にする
    func exportDummyFiles() {
        guard let app = selectedApp else { return }
        var seen = Set<String>()
        let extensions = fileTypes
            .filter { isChecked($0, in: app) }
            .compactMap(\.dummyExtension)
            .filter { seen.insert($0.lowercased()).inserted }
        guard !extensions.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.message = String(localized: "Choose a folder to export the dummy files to.")
        panel.prompt = String(localized: "Export", comment: "Open panel button: exports the dummy files to the chosen folder")
        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        // 複数のときは、選んだ場所に新しいフォルダを作ってまとめる（デスクトップなどを散らかさない。
        // 以前に書き出したファイルと混ざらないよう、同名のフォルダがあれば「ダミーファイル 2」のように別名にする）
        var folder = chosen
        if extensions.count > 1 {
            let folderName = String(localized: "Dummy Files", comment: "Name of the folder created to hold multiple exported dummy files")
            folder = Self.uniqueFolderURL(in: chosen, name: folderName)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "The folder for the dummy files could not be created.")
                alert.informativeText = error.localizedDescription
                alert.runModal()
                return
            }
        }

        let baseName = String(localized: "Dummy", comment: "File name (without extension) of the exported empty dummy files")
        let targets = extensions.map { folder.appendingPathComponent(baseName).appendingPathExtension($0) }

        // 中身のある同名ファイルは、確認してから置き換える（空のダミーファイルは黙って上書き）
        let nonEmpty = targets.filter { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0
        }
        if !nonEmpty.isEmpty, !confirmReplace(nonEmpty) { return }

        var failures: [String] = []
        for url in targets where !FileManager.default.createFile(atPath: url.path, contents: Data()) {
            failures.append(url.lastPathComponent)
        }

        let folderName = FileManager.default.displayName(atPath: folder.path)
        let exported = targets.count - failures.count
        status = (app.key, String(localized: "Exported \(exported) dummy files to \"\(folderName)\"."))
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Some dummy files could not be exported.")
            alert.informativeText = failures.joined(separator: "\n")
            alert.runModal()
        }
    }

    /// parent の中で使われていないフォルダの URL：「ダミーファイル」→「ダミーファイル 2」→「ダミーファイル 3」…（Finder と同じ付け方）
    nonisolated static func uniqueFolderURL(in parent: URL, name: String) -> URL {
        var url = parent.appendingPathComponent(name, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent("\(name) \(number)", isDirectory: true)
            number += 1
        }
        return url
    }

    // MARK: - Private

    private func visibleFileTypes(of app: TargetApp) -> [FileTypeInfo] {
        showAllFileTypes ? app.fileTypes : app.fileTypes.filter(\.isDocument)
    }

    private func isChecked(_ fileType: FileTypeInfo, in app: TargetApp) -> Bool {
        checked[app.key]?.contains(fileType.id) == true
    }

    private func saveApps() {
        PreferencesService.saveAppPaths(apps.map(\.key))
    }

    private func refreshHandlers() {
        var handlers: [String: URL] = [:]
        for app in apps {
            for ft in app.fileTypes where handlers[ft.id] == nil {
                handlers[ft.id] = AppScanner.currentHandler(for: ft.type)
            }
        }
        currentHandlers = handlers
        handlerNameCache = [:]
    }

    /// 「チェック済み」の区分に入れる種類。選んだアプリについて決めてあればそれ、
    /// まだなら（アプリを選んだ直後）今チェックの入っているもの
    private var pinnedTypeIDs: Set<String> {
        guard let app = selectedApp else { return [] }
        if let pinned, pinned.appKey == app.key { return pinned.ids }
        return currentCheckedIDs(of: app)
    }

    /// 今チェックの入っているものを「チェック済み」の区分に決める（更新ボタン・チェックの切り替えから呼ぶ。ビューの更新中には呼ばない）
    private func pinCheckedTypes() {
        guard let app = selectedApp else {
            pinned = nil
            return
        }
        pinned = (app.key, currentCheckedIDs(of: app))
    }

    private func currentCheckedIDs(of app: TargetApp) -> Set<String> {
        Set(app.fileTypes.filter { isChecked($0, in: app) }.map(\.id))
    }

    private func confirmReplace(_ urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Files with the same name already exist. Replace them?")
        alert.informativeText = urls.map(\.lastPathComponent).joined(separator: "\n")
        alert.addButton(withTitle: String(localized: "Replace"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var vm = ViewModel()

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 340)
        } detail: {
            detailView
        }
        .frame(minWidth: 640, minHeight: 300)
        .focusedSceneObject(vm)
    }

    // MARK: - Sidebar（ユーザーが追加したアプリ）

    private var sidebarView: some View {
        List(selection: $vm.selectedAppID) {
            ForEach(vm.apps) { app in
                // 追加したアプリは拡張子を取り出すためだけに使うので、バージョンは出さない
                Label {
                    Text(app.name)
                        .lineLimit(1)
                } icon: {
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                }
                .help(app.appURL.path)
                .contextMenu {
                    Button(String(localized: "Remove from Sidebar")) {
                        vm.removeApp(app.id)
                    }
                }
            }
            // 行のドラッグで並べ替える
            .onMove { vm.moveApps(fromOffsets: $0, toOffset: $1) }
            // Finder からのドロップは行の間に追加する（List 全体の dropDestination は並べ替えと競合するので使わない）
            .onInsert(of: [.fileURL]) { index, providers in
                loadAppURLs(providers) { vm.addApps($0, at: index) }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            // 空のときは行が無く onInsert が働かないので、ここでドロップを受ける
            if vm.apps.isEmpty {
                Text(String(localized: "Click + or drag apps here to add them."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .dropDestination(for: URL.self) { urls, _ in
                        let apps = urls.filter { $0.pathExtension.lowercased() == "app" }
                        guard !apps.isEmpty else { return false }
                        vm.addApps(apps)
                        return true
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    vm.presentAddPanel()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 20)
                }
                .help(String(localized: "Add App"))
                Button {
                    vm.removeApp(vm.selectedAppID)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 20)
                }
                .help(String(localized: "Remove from Sidebar"))
                .disabled(vm.selectedAppID == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    /// ドロップされたファイルのうち .app の URL を読み出す（読み終えたらメインスレッドで渡す）
    private func loadAppURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [(Int, URL)] = []
        for (i, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.pathExtension.lowercased() == "app" {
                    lock.lock(); urls.append((i, url)); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let sorted = urls.sorted { $0.0 < $1.0 }.map(\.1)
            if !sorted.isEmpty { completion(sorted) }
        }
    }

    // MARK: - Detail（ボタン＋対応ファイル一覧＋重複の通知＋ステータス）

    @ViewBuilder
    private var detailView: some View {
        if let app = vm.selectedApp {
            VStack(spacing: 0) {
                headerView
                Divider()
                listView
                if !vm.duplicateNotices.isEmpty {
                    Divider()
                    duplicateView
                }
                Divider()
                footerView
            }
            .navigationTitle(app.name)
            .searchable(text: $vm.searchText, placement: .toolbar,
                        prompt: Text(String(localized: "Search Extensions")))
            // 更新ボタンはツールバー（検索欄の左）に置く。ヘッダーの書き出しボタンの横では浮いて見えたため
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.refresh()
                    } label: {
                        Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                    }
                    .help(String(localized: "Refresh"))
                }
            }
        } else {
            Text(vm.apps.isEmpty
                 ? String(localized: "Add an app to the sidebar.")
                 : String(localized: "Select an app."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(Text(verbatim: "Default Apps"))
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Check the file extensions to export dummy files for."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(String(localized: "Export Dummy Files…")) {
                vm.exportDummyFiles()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(vm.checkedCount == 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    /// 対応ファイル一覧。チェック済み／書類／その他（「すべての対応ファイルを表示」のときだけ）の区分に分け、
    /// 列見出しのクリックで区分それぞれの中を並べ替える。「その他」は薄く表示する
    private var listView: some View {
        let sections = vm.sections
        return Table(of: FileTypeRow.self, sortOrder: $vm.sortOrder) {
            TableColumn("") { row in
                CheckCell(
                    fileType: row.fileType,
                    isChecked: Binding(
                        get: { vm.isChecked(row.fileType) },
                        set: { vm.setChecked(row.fileType, $0) }
                    )
                )
                .opacity(dimmedOpacity(row))
            }
            .width(20)

            TableColumn(String(localized: "Extension", comment: "File list column header"),
                        value: \.extensionsText, comparator: .localizedStandard) { row in
                ExtensionCell(fileType: row.fileType)
                    .opacity(dimmedOpacity(row))
            }
            .width(min: 90, ideal: 130)

            TableColumn(String(localized: "Kind", comment: "File list column header: file type description"),
                        value: \.kind, comparator: .localizedStandard) { row in
                Text(row.kind)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(row.kind)
                    .opacity(dimmedOpacity(row))
            }
            .width(min: 120, ideal: 200)

            TableColumn(String(localized: "Default App", comment: "File list column header: app that currently opens the file type"),
                        value: \.handlerName, comparator: .localizedStandard) { row in
                Text(row.handlerName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(row.handlerName)
                    .opacity(dimmedOpacity(row))
            }
            .width(min: 120, ideal: 250)
        } rows: {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        TableRow(row)
                    }
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .overlay {
            if sections.isEmpty && !vm.searchText.isEmpty {
                Text(String(localized: "No Results"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 書類として開かない種類（「その他」の区分。チェック済みの区分に入っていても）は v1 と同じく薄く表示する
    private func dimmedOpacity(_ row: FileTypeRow) -> Double {
        row.fileType.isDocument ? 1 : 0.45
    }

    /// 他のアプリでも同じ拡張子にチェックが入っているときの通知（モーダルにせず、ここに出すだけ）
    private var duplicateView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(vm.duplicateNotices) { notice in
                Label {
                    Text(String(localized: "\(notice.extensionsText) is also checked for \(notice.appNames.formatted(.list(type: .and))).",
                                comment: "Notice: the same extension is checked for another app in the sidebar (1st %@ = extensions, 2nd %@ = app names)"))
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Footer（ステータスバー：件数・書き出しの結果）

    private var footerView: some View {
        HStack {
            Text(String(localized: "\(vm.fileTypes.count) file types, \(vm.checkedCount) checked"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if let message = vm.statusMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        // ステータスバーをつまんでウインドウを動かせるようにする（タイトルバーと同じ）
        .modifier(WindowDraggable())
    }
}

/// ドラッグでウインドウを動かせるようにする。
/// - macOS 15 以降：標準の WindowDragGesture（文字の上からでも動かせる）
/// - macOS 14 以下：背景の NSView で動かす（文字の上では動かない。ユーザー了承済み）
private struct WindowDraggable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        } else {
            content.background(WindowDragArea())
        }
    }
}

/// ドラッグでウインドウを動かす領域（背景に敷く。macOS 14 以下用）
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

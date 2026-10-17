import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var vm = ViewModel()
    @AppStorage(PreferencesService.showAllFileTypesKey) private var showAllFileTypes = false

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            detailView
        }
        .frame(minWidth: 600, minHeight: 300)
        .focusedSceneObject(vm)
    }

    // MARK: - Sidebar（複数バージョンがあるアプリ群）

    @ViewBuilder
    private var sidebarView: some View {
        if vm.families.isEmpty {
            Text(String(localized: "No apps with multiple versions were found."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(vm.families, selection: $vm.selectedFamilyID) { family in
                Label {
                    Text(family.name)
                        .lineLimit(1)
                } icon: {
                    Image(nsImage: family.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Detail（バージョン選択＋関連付けボタン＋対応ファイル一覧）

    @ViewBuilder
    private var detailView: some View {
        if let family = vm.selectedFamily {
            VStack(spacing: 0) {
                headerView(family)
                Divider()
                listView(family)
                Divider()
                footerView
            }
            .navigationTitle(family.name)
        } else {
            Text(String(localized: "Select an app."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(Text(verbatim: "Default Apps"))
        }
    }

    private func headerView(_ family: AppFamily) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: $vm.selectedURL) {
                ForEach(family.versions) { version in
                    Label {
                        Text(version.displayName)
                    } icon: {
                        Image(nsImage: menuIcon(version.icon))
                    }
                    .tag(Optional(version.appURL))
                }
            }
            .labelsHidden()

            Button {
                vm.associate()
            } label: {
                // ボタンの見た目の幅を 80pt に固定する（ベゼルの左右余白 8pt ずつを除いた 64pt をラベルに指定）
                Text(String(localized: "Associate"))
                    .frame(width: 64)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(vm.fileTypes.isEmpty || vm.isAssociating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    /// 対応ファイル一覧。通常はアプリ群に関連付け済みのものだけ。
    /// 「すべての対応ファイルを表示」のときは、関連付け済み（関連付けの対象）と
    /// 他のアプリに関連付け済み（薄く表示・関連付けの対象外）の2つのセクションに分ける
    private func listView(_ family: AppFamily) -> some View {
        // 拡張子の列の幅は表示している行で決める（「すべて表示」の切り替えで、そのとき出ている行に合わせて変わる）
        let shown = showAllFileTypes ? vm.fileTypes + vm.otherFileTypes : vm.fileTypes
        let extensionColumnWidth = FileTypeRowView.extensionColumnWidth(for: shown)
        return List {
            if showAllFileTypes {
                Section(String(localized: "Associated with \(family.name)")) {
                    rows(vm.fileTypes, isDimmed: false, extensionColumnWidth: extensionColumnWidth)
                }
                if !vm.otherFileTypes.isEmpty {
                    Section(String(localized: "Associated with Other Apps")) {
                        rows(vm.otherFileTypes, isDimmed: true, extensionColumnWidth: extensionColumnWidth)
                    }
                }
            } else {
                rows(vm.fileTypes, isDimmed: false, extensionColumnWidth: extensionColumnWidth)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .environment(\.defaultMinListRowHeight, 22)
    }

    private func rows(_ fileTypes: [FileTypeInfo], isDimmed: Bool, extensionColumnWidth: CGFloat) -> some View {
        ForEach(fileTypes) { ft in
            FileTypeRowView(
                fileType: ft,
                handlerName: vm.handlerName(for: ft),
                isAssociated: vm.isAssociatedWithSelected(ft),
                isDimmed: isDimmed,
                extensionColumnWidth: extensionColumnWidth
            )
            .listRowSeparator(.hidden)
            // 行の上下の既定余白をなくし、行の高さは FileTypeRowView の frame で決める
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    // MARK: - Footer（ステータスバー：件数・処理中表示）

    private var footerView: some View {
        HStack {
            Text(String(localized: "\(vm.fileTypes.count) file types"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if vm.isAssociating {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    /// ポップアップメニュー用に 16pt のアイコンを作る
    private func menuIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

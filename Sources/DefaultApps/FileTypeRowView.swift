import SwiftUI
import AppKit

/// 一覧（テーブル）の拡張子の列：書類アイコン＋拡張子
struct ExtensionCell: View {
    let fileType: FileTypeInfo

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(for: fileType.type))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text(fileType.extensionsText)
                .lineLimit(1)
                .help(fileType.extensionsText)
        }
    }
}

/// 一覧（テーブル）のチェックボックスの列。拡張子の無い種類はダミーファイルを作れないので選べない
struct CheckCell: View {
    let fileType: FileTypeInfo
    @Binding var isChecked: Bool

    var body: some View {
        Toggle("", isOn: $isChecked)
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(fileType.dummyExtension == nil)
    }
}

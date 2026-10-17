import SwiftUI
import AppKit

struct FileTypeRowView: View {
    let fileType: FileTypeInfo
    let handlerName: String
    let isAssociated: Bool
    /// 他のアプリに関連付けられている行（「すべての対応ファイルを表示」の下のセクション）は薄く表示する
    var isDimmed = false
    /// 拡張子の列の幅（extensionColumnWidth(for:) で、アプリ群の中で一番長い拡張子の表示に合わせる）
    var extensionColumnWidth: CGFloat = minExtensionColumnWidth

    private static let font = NSFont.systemFont(ofSize: 13)
    private static let minExtensionColumnWidth: CGFloat = 110

    /// 拡張子の列の幅。どの行も省略されないよう、一番長い拡張子の表示（".pbm, .pgm, .ppm, .pfm" など）に合わせる。
    /// 短いときは従来の 110pt
    static func extensionColumnWidth(for fileTypes: [FileTypeInfo]) -> CGFloat {
        let widest = fileTypes
            .map { ($0.extensionsText as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return max(minExtensionColumnWidth, (widest + 8).rounded(.up))
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(for: fileType.type))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)

            Text(fileType.extensionsText)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(width: extensionColumnWidth, alignment: .leading)

            Text(fileType.description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            // 現在の関連付け先（選択中の Photoshop と一致していればチェック）
            Text(handlerName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isAssociated ? Color.accentColor : Color.clear)
                .frame(width: 12)
        }
        .frame(height: 24)
        .opacity(isDimmed ? 0.45 : 1)
    }
}

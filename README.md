# Default Apps

同じアプリの複数バージョンがインストールされた Mac で、指定したバージョンに対応ファイルを関連付ける macOS 用ユーティリティです（Adobe Photoshop、Illustrator、InDesign など）。

アプリを複数バージョンインストールしていると、対応ファイルは最新バージョンに関連付けられます。旧バージョンをメインに使いたいときに、関連付け先をまとめて切り替えられます。

## 使い方

1. 左のサイドバーから、アプリを選ぶ（例：Adobe Photoshop）
2. 上部のポップアップから、バージョンを選ぶ（例：Adobe Photoshop 2025 (26.11.8)）
3. 「関連付け」ボタンを押す

- ファイル形式の一覧には、すでにそのアプリ（いずれかのバージョン）に関連付けされている形式が表示されます。ポップアップの選択バージョンですでに関連付けされている形式にはチェックが付きます。
- 他のアプリに関連付けされている形式は変更しません。
- 表示メニューの「すべての対応ファイルを表示」（⌘⇧A）で、他のアプリに関連付けされている形式も薄く表示します（関連付けの対象にはなりません）。
- 表示メニューの「更新」（⌘R）で、アプリと関連付け先を読み込み直します。

## 対象のアプリ

- `/Applications` と `~/Applications` にある、同じ Bundle ID のアプリが複数あるもの
- ベータ版など、Bundle ID の末尾だけが違うもの（例：`com.adobe.illustratorBeta`）も同じアプリとして扱います。

## 仕組み

各アプリはどのバージョンも同じ Bundle ID を使用しているため、Bundle ID で指定する `LSSetDefaultRoleHandlerForContentType` ではバージョンを区別できません。Default Apps は、アプリの場所で指定できる `NSWorkspace.setDefaultApplication(at:toOpen:)` で関連付けます（Finder の「情報を見る → すべてを変更」と同じ仕組みです）。

## 既知の制限

- macOS 26.4 以降では、macOS のセキュリティにより、書類の種類ごとに関連付けの変更を確認するダイアログが表示されることがあります。ダイアログで変更を許可すると、関連付けが変更されます。
- ダイアログが表示されずに、関連付けが反映されないこともあります。その場合は Default Apps が警告を表示します。Finder で対象のファイルの「情報を見る」を開き、「このアプリケーションで開く」でバージョンを選んで「すべてを変更」をクリックしてください（Finder からの変更では、確認のダイアログは表示されません）。

## 動作環境

macOS 13.5 Ventura 以降（Universal Binary）

## ライセンス

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

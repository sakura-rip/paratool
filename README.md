# Paratool

Mac標準の `⌘⇧4` から、注釈・コピーまで。スクショを画面左下に最新3枚まで保持する、Macネイティブのメニューバーアプリです。

## 使い方

1. `Paratool.app` を起動し、スクショの保存先へのアクセスを許可します。
2. `⌘⇧4` で撮影すると、左下にサムネイルが追加されます。
3. サムネイルをクリックし、図形・矢印・ペン・文字・目隠しを追加します。
4. 「完了してコピー」でチャットなどに貼り付けるか、「保存」でPNGを書き出します。

サムネイルは自動では消えず、4枚目で最も古い表示が外れます。元の画像ファイルは削除しません。履歴と注釈はアプリ終了までメモリに保持します。

macOS標準の右下プレビューを出さない場合は、`⌘⇧5 → オプション → フローティングサムネールを表示` をオフにしてください。このプロジェクトを作成したMacではユーザーの指定でオフに設定済みです。アプリは他のMacの設定を無断で変更しません。

## ダウンロード・配布

[GitHub Releases](https://github.com/sakura-rip/paratool/releases) のZIPを解凍し、`Paratool.app` をアプリケーションフォルダへ移動してください。

| Mac | ダウンロード |
| --- | --- |
| Apple Silicon（M1以降） | `Paratool-X.Y.Z-macos-arm64.zip` |
| Intel | `Paratool-X.Y.Z-macos-x86_64.zip` |

macOS 13以降に対応。現状はローカル署名（ad hoc）のみで、Developer ID署名・Apple公証は行っていません。初回起動がブロックされた場合は、配布元を確認し「システム設定 → プライバシーとセキュリティ → このまま開く」から許可します。通常の起動体験で一般配布するには、今後Apple Developer Programの証明書による署名と公証を追加してください。

## ローカル開発

Xcode Command Line Tools / Swift 5.9以降が必要です。外部パッケージ依存はありません。

```sh
./scripts/test.sh
./scripts/build-app.sh
open dist/Paratool.app
```

配布用ZIPもローカルで生成できます。

```sh
APP_VERSION=0.1.0 ./scripts/package-release.sh
```

GUIスモークテスト（ログイン済みのMacのデスクトップ環境が必要）:

```sh
.build/debug/Paratool --smoke-test
```

一時フォルダにスクショと同じメタデータを持つテスト画像を作り、監視・重複除外・既存ファイル除外・最大3枚・編集ウィンドウ・PNG出力を確認します。画面キャプチャは行いません。結果の画像は `dist/verification/` に出力します。`--demo` でサンプル画像を表示できます。

## GitHub Actions

- `main` のpush・Pull Request・手動実行で、Apple SiliconとIntelの両方をテスト・ビルドします。ZIPは各実行のArtifactsから取得できます。
- `vX.Y.Z` タグのpushで、両方のZIPとSHA-256チェックサムを **GitHub Releaseの下書き** に添付します。
- 両アーキテクチャのビルド成功後にのみ下書きを作成します。公開済みリリースのファイルは上書きしません。
- 外部の認証情報は不要です。標準の `GITHUB_TOKEN` を使い、リリース作成ジョブだけに `contents: write` を与えています。

```sh
git tag v0.1.0
git push origin v0.1.0
```

[Actions](https://github.com/sakura-rip/paratool/actions) が成功したら [Releases](https://github.com/sakura-rip/paratool/releases) の下書きを開き、ダウンロード内容を確認して「Publish release」で公開します。一般利用者には下書きは見えません。

## ショートカット

| 操作 | キー |
| --- | --- |
| 撮影 | macOS標準 `⌘⇧4` |
| 元に戻す / やり直す | `⌘Z` / `⇧⌘Z` |
| PNG保存 | `⌘S` |
| コピー（エディタを維持） | `⌘C` |
| 完了してコピー | `⌘Return` |
| 全体表示 | `⌘0` |
| 拡大 / 縮小 | `⌘+` / `⌘-` |
| 選択した注釈を削除 | `Delete` |

## 検知の仕組みと制限

保存先フォルダを0.75秒間隔で確認し、書き込みが安定し、スクリーンショットのメタデータがある画像だけを取り込みます。起動前から存在する画像、通常の画像、書き出した注釈画像は自動取り込みしません。macOSの保存先設定の変更には約5秒で追従します。アプリで手動指定したフォルダがある場合は、その指定を優先します。

画像が出ない場合は、メニューバーから保存先を選び直してください。メニューの「画像を開く…」から既存画像を編集することもできます。PNG・JPEG・HEIC・TIFFを扱い、クリップボードだけへの保存、動画、PDFは自動取り込みの対象外です。

左下の一覧はメインディスプレイに表示します。スクリーンショットを撮る範囲に一覧が含まれる場合、通常のウィンドウと同じく写り込みます。

macOS標準プレビューと保存タイミングの説明: [Appleのスクリーンショットガイド](https://support.apple.com/guide/mac-help/mh26782/mac)。GitHub runner構成: [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

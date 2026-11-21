# sarashina-cli

Sarashina APIで日本語文章を添削する、Swift製のエージェント・自動化向けCLIです。

## 必要環境

- Swift 6.2以降
- Sarashina APIキー

## ビルド

```powershell
swift build -c release
```

実行ファイルは `.build\release\sarashina.exe` に生成されます。

## APIキーを安全に保存する

Windows DPAPIをSwiftから直接利用し、現在のWindowsユーザーだけが復号できる形で保存します。入力内容は画面に表示されません。

```powershell
sarashina auth set
sarashina auth status
```

保存したキーを削除する場合:

```powershell
sarashina auth delete
```

`SARASHINA_API_KEY` が設定されている場合は、保存済みキーより環境変数を優先します。APIキーを表示するコマンドはありません。

## 添削

```powershell
sarashina proofread "昨日は会議で話しをしました。"
```

標準入力とJSON出力:

```powershell
"昨日は会議で話しをしました。" |
  sarashina proofread --stdin --format json
```

文体指定:

```powershell
sarashina proofread --style polite --file document.txt
sarashina proofread --style plain --file document.txt
```

## Piから利用する

```powershell
pi --skill ./skills/sarashina-proofread
```

```powershell
"添削対象の文章" |
  pi --skill ./skills/sarashina-proofread -p `
  "入力された文章をSarashinaで添削し、修正点も説明してください"
```

## 終了コード

| Code | 意味 |
|---:|---|
| 0 | 成功 |
| 1 | その他のエラー |
| 2 | 引数・入力・設定エラー |
| 3 | API認証エラー |
| 4 | 一時的なAPI・ネットワークエラー |

## 開発

```powershell
swift test
swift build -c release
```

- ドキュメント: https://docs.sarashina.ai/
- Chat Completions: `POST https://api.sarashina.ai/v1/chat/completions`

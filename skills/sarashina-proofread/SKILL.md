---
name: sarashina-proofread
description: Sarashina APIを使って日本語文章を添削・校正する。ユーザーがSarashinaでの添削、誤字脱字の修正、文章の推敲、敬体・常体への統一を依頼したときに使用する。
---

# Sarashina proofreading

`sarashina auth status --format json` で資格情報が設定済みか確認する。APIキーそのものを表示したり要求したりしない。

文章は標準入力で渡し、エージェントから利用するときはJSON出力を使う。

```sh
printf '%s' "$TEXT" | sarashina proofread --stdin --format json
```

敬体へ統一する場合は `--style polite`、常体へ統一する場合は `--style plain` を指定する。

結果の `corrected_text`、`changes`、`comments` を読み、ユーザーの指定した形式で提示する。失敗した場合は標準エラーと終了コードを確認し、資格情報の内容をログや回答へ出力しない。

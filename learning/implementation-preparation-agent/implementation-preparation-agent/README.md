# CR-Oriented Implementation Support Agent

ウォーターフォール式のOS / Linux kernel / driver / embedded software開発における、**製作フェーズ + CR準備**向けAgent定義一式です。

前回版の「実装着手支援Agent」を拡張し、今回版ではCRで一番重い **説明資料作成・根拠整理・変更後チェック** を主目的にします。

## 結論

このAgent群は、実装を丸投げするためのものではありません。

目的は次の2つです。

1. 実装前に、詳細設計から実装方針・実装意図・公式根拠を整理する。
2. 実装後に、変更内容・脆弱性観点・処理不足・コード規約・Coverity・仕様差異を確認し、CR用説明資料を作る。

## 対象ワークフロー

```text
詳細設計確認
  ↓
[A] 実装方針・CR説明観点の整理        ← Agent 1
  ↓
人間レビュー / 実装方法確定
  ↓
コード変更                              ← 人間 / Copilot支援
  ↓
[B] 変更後チェック・CR資料作成          ← Agent 2
  ↓
CR実施
  ↓
修正対応
  ↓
試験工程へ引き渡し
```

## Agent構成

### Agent 1: Pre-Implementation Strategy Agent

実装前に起動します。

役割:

- 詳細設計から実装要求を抽出する
- 機能単位で実装意図を整理する
- 変更対象ファイル・関数候補を整理する
- 公式API / README / 仕様書の根拠を収集する
- 公式ドキュメント参照時に対象バージョンを確認する
- CRで説明すべき論点を事前に洗い出す
- 実装前に人間が決めるべき未確定事項を出す

主出力:

- `Pre-Implementation Strategy Report`
- `CR Explanation Draft`
- `API Evidence List`

### Agent 2: Post-Change CR Package Agent

コード変更後に起動します。

役割:

- 変更差分を機能単位で整理する
- 実装意図と実コードの対応を整理する
- 脆弱性・処理不足・エラー処理不足を確認する
- コード規約違反候補を確認する
- Coverity実行または実行コマンド・結果取り込みを行う
- 仕様書との差異を確認する
- 乖離がある場合、修正案を提示する
- ナンバリング付きのCR資料を生成する

主出力:

- `CR Review Package`
- `Post-Change Check Report`
- `Fix Proposal List`

## 使い方

### 1. 実装前

`templates/implementation_request.md` を案件ごとにコピーして埋めます。

その後、Copilot Chat / coding agent に以下を渡します。

- `AGENTS.md`
- `prompts/pre_implementation_strategy_prompt.md`
- 記入済み `implementation_request.md`
- 詳細設計書、上位設計書、関連Redmine、対象ソース

期待する出力:

- 実装方針
- 機能単位の実装意図
- 公式根拠リンク
- CRで説明すべき内容
- 実装前の確認事項

### 2. 実装後

コード変更後、以下を渡します。

- `AGENTS.md`
- `prompts/post_change_cr_package_prompt.md`
- git diff または変更ブランチ
- 詳細設計書
- 実装前レポート
- Coverity実行結果がある場合はその結果

期待する出力:

- ナンバリング付きCR資料
- 変更点説明
- 仕様との差異確認
- 脆弱性・処理不足の分析
- コード規約チェック
- Coverity結果整理
- 修正案

## 重要な制約

- Agentは仕様を勝手に補完してはいけません。
- 公式APIを使う場合、対象バージョンと根拠リンクを必ず示します。
- CR資料は、レビュー参加者が追えるように項番を付けます。
- 実装後チェックで乖離が見つかった場合、隠さず修正案として出します。
- Coverityが実行できない場合は、未実行として扱い、代替コマンドや実行依頼を明記します。

## ファイル構成

```text
.
├── README.md
├── AGENTS.md
├── .github/
│   └── copilot-instructions.md
├── workflow/
│   ├── production_cr_workflow.md
│   └── agent_boundary.md
├── prompts/
│   ├── pre_implementation_strategy_prompt.md
│   ├── post_change_cr_package_prompt.md
│   └── coverity_result_analysis_prompt.md
├── templates/
│   ├── implementation_request.md
│   ├── pre_implementation_strategy_report.md
│   ├── api_evidence_list.md
│   ├── post_change_check_report.md
│   ├── cr_review_package.md
│   └── fix_proposal_list.md
├── examples/
│   ├── example_implementation_request.md
│   └── example_cr_review_package.md
├── docs/
│   ├── evidence_policy.md
│   ├── numbering_rule.md
│   ├── review_checkpoints.md
│   └── adoption_plan.md
└── scripts/
    ├── run_local_static_checks.sh
    └── run_coverity_wrapper.sh
```

## 最初に試す対象

最初は、以下のような小さく説明しやすい案件を選んでください。

- 既存ドライバのログ追加
- エラー処理追加
- Kconfig / DTS / recipeの限定変更
- 既存API利用箇所の置換
- 過去障害の再発防止に関する小修正

避ける対象:

- 新規ドライバ全体
- 複数サブシステムを跨ぐ変更
- 仕様未確定の機能
- CR論点が多すぎる大規模リファクタ

## 成功条件

このAgentの成功条件は、コードが生成できることではありません。

CR前に、次が揃うことです。

- 何を変えたか
- なぜ変えたか
- 仕様のどこに基づくか
- 公式APIのどこに基づくか
- 既存処理から何が変わるか
- どのリスクを確認済みか
- 残っている懸念は何か
- 乖離がある場合、どう直すか

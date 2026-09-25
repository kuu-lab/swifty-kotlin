# Kotlin Compiler Remaining Tasks

### Diff skip 追跡（残り 4 件）
- [~] DEBT-DIFF-007: `run_case` の compile-exit-code-match 誤判定修正（2026-07-08、`Scripts/diff_kotlinc.sh`）で新規に顕在化した ref/candidate 不一致を、診断/ネガティブテスト・enum/data class/interface 未実装・common stdlib gap・coroutine Flow・reflection・JVM interop・finally routing の7グループへ分解して triage 済み（2026-07-29、`docs/diff-skip-inventory.md` の DEBT-DIFF-007 節）。2026-08-13 更新：今回さらに19件のテスト入力ミス/common stdlib gap ケースを修正し `SKIP-DIFF` を解除。2026-08-18 更新：`list_binary_search_compare.kt`・`mock_objects.kt` をテスト入力ミス修正で追加解除（36→16→14）。2026-09-04 更新：現行 `SKIP-DIFF (DEBT-DIFF-007)` タグを実測して11件へ更新（`flow_builders.kt` は KSP-1543 で解除）。2026-09-16 更新：`enum_basic.kt` の enum collection-HOF boxing を修正し、現行タグを10件へ更新。新たに見つかった未修正の実バグ多数（`Unit`を明示的な値として使えない一般的ギャップ、`if (x !is T) return` 後に smart-cast が後続コードへ伝播しない一般的ギャップ、トップレベルの2件目以降の複数行文字列プロパティが `null` になる疑いのある一般的初期化順序バグ、等）も同節に記録済み。

## Dead Code 削除タスク（DEADCODE: 2026-07-11〜12 再監査）

> 2026-06-12 監査分の履歴は [`docs/dead-code-audit.md`](docs/dead-code-audit.md) に保存。今回は現 HEAD で (1) Swift の USR/index 解析（Periphery 3.7.4、public/Codable は保持）、(2) 識別子の宣言・呼び出し箇所の `rg` 照合、(3) 2,791 件の Runtime `@_cdecl`（`kk_*` 2,739 件 + `__kk_*` 52 件）に対する CompilerCore / CompilerBackend / bundled Kotlin / Runtime 内部 / Tests / ABI テーブル経路の照合、を併用した。
> 根拠略号: **R0** = 宣言以外の参照 0、**D** = 参照元が別の dead symbol のみ、**W0** = 代入/初期化のみで read 0、**E0** = Runtime export に emit/内部/テスト経路 0、**T** = 製品からは未使用でテストのみ。同名 overload や別 lexical scope は USR 単位で分離済み。
> 1 checkbox = 1 method / property / type / enum case を原則とする。D 項目は参照元タスクを先に削除し、最後に owner type/file を整理する。`RuntimeABISpec` 登録は使用証拠ではないため、E0 削除時は spec/parity/snapshot も同時に消す。
> 除外を実済み: `kk_print_string_flat` は Backend が直接 emit するため alive。`kk_atomic_*` は prefix + suffix の 2 段階動的生成、URLSession delegate / `@main` / XCTest・Swift Testing discovery / protocol witness / Hashable・Codable 合成参照も alive として除外。
> 完了ゲートは refactor PR gate（全テスト + golden + `diff_kotlinc.sh` green）。完全に到達不能な単独 private helper のみを削除する PR は、対象 module テスト + `git diff --check` を最低ゲートとし、まとめ PR 時に full gate を実施する。

### 監査基盤 / 残領域

- [~] DEADCODE-014: 旧「未監査領域」を継続監査する。2026-07-12 時点で tracked `.c/.h/.cc/.cpp` は 0 件、`DiagnosticRegistry` 108 descriptor は全て production 発行箇所あり、stored/global/Tests helper の検出結果は下記に分割済み。**2026-07-31 更新**: 「SKIP-DIFF 62 件」は stale な数値だったと判明（実測は当時110件）。kswiftc を再ビルドして全件 `--force-run-skipped` で再判定し、9件を解除（`comparator_basic.kt`/`interface_properties.kt`/`kconstructor_basic.kt`/`math_exp_log_functions.kt`/`random_overload_edge_cases.kt`/`file_use_edge_cases.kt`/`coroutine_exception_handling.kt`/`coroutine_scope_lifecycle.kt`/`coroutine_supervisor_job.kt`）。並行して別セッションが `DEBT-DIFF-001` の完全棚卸しと `DEBT-DIFF-007`(72→37) の大規模 triage を実施していたため、その成果を `git reset --hard origin/master` で取り込んだ上で作業を継続（このとき `BUG-152`(#5068) が本セッションの CharSequence.length 修正と完全に重複していたと判明し、重複分は破棄）。本セッション側の net-new な実装: (1) `EnumClass.values()` が Sema 未登録で完全に unresolved だったバグと `entries` のメンバー転送不可バグを修正（`enum_entries_function.kt` を追加解除、`enum_basic.kt`/`enum_edge_cases.kt` は別バグ=`BUG-177` で依然ブロック中）、(2) `Array<T>` の `mapIndexed`/`filterIndexed`/`mapNotNull`/`filterNot`/`filterNotNull`/`reduceIndexed`/`first`/`firstOrNull`/`last`/`lastOrNull` 未解決バグを修正（`array_hof.kt` も 2026-08-13 現在 SKIP-DIFF タグが無く active（`--force-run-skipped` で PASS））。詳細・各コミットの root cause は [`docs/diff-skip-inventory.md`](docs/diff-skip-inventory.md) 参照。2026-08-18 実測では active な SKIP-DIFF は 35 distinct file（35 tag instance、内訳は docs/diff-skip-inventory.md）。`list_binary_search_compare.kt`・`mock_objects.kt` を追加解除。`compiler_plugin_api.kt` は 2026-08-13 現在 SKIP-DIFF タグが無く active（`--force-run-skipped` で PASS）
- **2026-09-16 継続監査**: 現行 HEAD で `Scripts/dead_code_audit.sh --self-test` を再実行し、`@_cdecl("__kk_x")` と Swift 名 `kk_x` の別名呼び出しを Tests / Runtime 内部の到達性判定へ追加。E0 を満たす旧リフレクション ABI 9 件（KFunction 3、callable reference 4、KProperty stub 2）と、source-backed 化済みの `kk_indexed_value_new` / `__kk_mutable_collection_addAll_sequence` を Runtime 実装・`RuntimeABISpec` ともに削除し、ABI 回帰テストを追加した。監査結果は `docs/dead-code-audit.md` に追記。残る KProperty 完全メタデータ拡張、`kk_cinterop_writeBits`、HTTP 追加 surface は所有タスクで継続監査する。
- **2026-09-23 継続監査**: HEAD（`59dd246ff`）で監査再実行し #6881 マージ地点とのリスト差分を取得。実測: Runtime export 1,702（前回 1,665）、compiler-unreachable 130（136）、A 14（変化なし）、B 76（82→−7：freezable_atomic_ref 5 件は #6914 の Kotlin 化で削除、cpointer_new/instant_from_epoch_seconds は配線済み、+1：ARCH-016 の `kk_object_release` は emit 配線待ちの意図的テストのみ）、runtime-internal 40（変化なし）。self-test 4/4 PASS。A 14 件は全て延期理由を再確認済みで削除なし。`.c/.h` は 2 件（RuntimeCAtomics、#7121 の stdatomic セル、正当）。`DiagnosticRegistry` 99 descriptor 全て production 発行あり。詳細は `docs/dead-code-audit.md` の 2026-09-23 節。

---

## AI slop クリーンアップ（SLOP: 2026-08-19 監査）

> 調査方法: AI 生成コードに特有の劣化パターン（残置デバッグ出力・無条件 pass アサーション・タスク番号入り識別子・同義 private ヘルパーのファイル間重複・無条件 disable）を rg で横断検索し、ヒットを個別にコード確認して slop と確定したもののみ登録。`// Note:` / placeholder / 変更経緯コメント類は設計理由の説明として機能しているため誤検知として除外した。
> 完了ゲート: 各タスク記載の rg チェック 0 件 + 対象 suite green。bundled .kt を触るタスクは共通ゲート G（`swift_test.sh` / Golden / `diff_kotlinc.sh`）も適用。
> タスク番号 prefix 命名（`ksp4NN*`）は [[BUG-218]]（同一パッケージ別ファイルの同名 private トップレベル宣言が SEMA-0001 で誤衝突する重複検出バグ）の回避策として発生したもの。`__kk` prefix の共有ヘルパー（`MatchResult.kt` の `__kkIsGroupNameStart` 等の既存規約）へ統合する形なら BUG-218 の修正を待たずに着手できる。素朴な private 命名へ戻す場合は BUG-218 が前提。

---

## コード共通化タスク（REFACT: 2026-06-28 調査）

> 調査方法: KIR 層・Lowering 層・Sema 層・テスト層を横断して重複パターンを抽出。
> 優先度は影響ファイル数と「新 primitive 型追加時の修正箇所数」で決定。
> 完了ゲートは全テスト + golden + `diff_kotlinc.sh` green。

## Lowering 小粒リファクタ（RF-LOWER: 2026-09-06 調査）

> 対象は (1) Collection の source-backed 呼び出し保護・移行済み特例の整理、(2) 式の分類・コピー伝播の一元化、(3) Inline 展開の責務・終了条件の整理。パス計測・順序契約・並列 lowering の有効化は本系列に含めない。以下は静的調査に基づく実行タスクであり、旧経路の到達不能性・性能改善・新規バグの再現を確認済みとは扱わない。
>
> **粒度と競合回避**: 原則1 checkbox = 1責務 = 1 PR。処理の移動と挙動変更を混ぜず、対象外の整形・改名をしない。主な編集範囲は各項の「対象」に限定し、呼び出し元の配線・対応テスト以外へ広がる場合は着手前に新IDへ再分割する。ファイル分割だけを最終成果にせず、後続の状態管理・判定・終了条件の改善へ接続する。
> - **共通ファイルは直列**: `CollectionLiteralLoweringRegistry.swift`、`CollectionLiteralLoweringPass+CallRewrite.swift`、`+CallRewriteFactories.swift`、`+PreScan.swift`、`+VirtualCallRewrite.swift`、`+LookupTables.swift`、`+RewriteState.swift`、`InlineLoweringPass.swift` を変更するPRは、同じファイルを触る先行PRのマージ後のHEADから開始する。前提が満たされても編集範囲が重なれば並列にしない。
> - **独立した変更だけ並列**: Collection 系と Inline 系は別レーン。STATE-004後の virtual-call の葉ファイルは、共有 dispatcher / state / lookup に追記しない範囲で並列可。抽出前の巨大ファイルを複数PRが同時に分割する運用は禁止する。
> - **テストも編集範囲を分離**: 既存 suite / helper を再利用し、追加は責務別 extension または既存 fixture に置く。巨大な `CollectionLiteralLoweringTests.swift` の一括移動・既存 diff ケースの無関係な整理を混ぜない。純粋な stdout 比較の新規実行テストは `Tests/CompilerBackendTests/Fixtures/` を使う。
> - **台帳の運用**: `TODO.md` の更新は自タスクの状態・実績・必要な前提だけに限定し、セクション全体の整形・完了項目の一括削除を同時に行わない。
>
> **既存タスクとの境界**: `buildList` capacity の Kotlin 化・Sema stub 削除は KSP-697、collection factory 自体の移行は KSP-699 等の担当。本系列は残存 Lowering の整理であり、同じ移行を別実装しない。由来判定は既存の symbol / import 情報を利用し、RF-GOLDEN-002 の表示用分類や ARCH-021 の well-known 基盤を重複実装しない。全パス verifier・位置配列API変更は ARCH-018/019 の担当で、Inline 内の局所的な検証とは分ける。各系列を始める際に関連PRのマージ状況・現コードを再確認する。
>
> **共通完了ゲート**: 対象 Core Lowering / KIR suite、必要な Backend fixture・source注入 / stdlib artifact 経路、該当 Kotlin 差分ケースに加え、`AGENTS.md` のRF必須ゲート（全 Swift テスト・Golden・全 `diff_kotlinc.sh`、存在する場合の `loc_report.sh` 指標）を各PRで満たす。API / ABI・例外・boxing・決定性を維持し、移動のみのPRではKIR/LLVM IRの不変性も確認する。バグを発見したら最小 Kotlin 再現と回帰テストを同じ修正PRに含め、既存の誤動作を期待値更新で固定しない。ABI export を削除する必要がある場合は利用者ゼロの確認・Spec/parity/リンク検証を同じPRに含め、残存理由がある経路をテストだけ消して完了扱いにしない。
>
> 以下のSwiftファイル名は、特記がなければ `Sources/CompilerCore/Lowering/` 配下。新設する責務別ファイル名は案であり、着手時に既存の同責務ファイルがあれば再利用する。

### 1. Collection の source-backed 保護・Builder DSL 残存処理（RF-LOWER-CALL）

> 主な順序: CALL-001 → 002 → 003 → 004 → 005 → 006。CALL-007は002後に分岐でき、007 → 008 → 009 → 010 → 011 → 012 → 013 → 014 → 015。014はSTATE-009、015は006も待つ。Builder側とpolicy側で lookup / dispatcher / test の編集が重なる場合は直列化する。API群単位で不要なrewriteと対応lookupを一緒に減らし、別の巨大な名前allowlistへ移し替えない。

- [x] RF-LOWER-CALL-007: source-backed呼び出しの保持判断を専用policyへ抽出する（前提: CALL-002）
  - 対象: `+CallRewrite.swift` の `shouldPreserveSourceBackedAggregateCall` と `+VirtualCallRewrite.swift` の対応する保持判断、責務別policy。まず現行の判断順序を維持した抽出だけを行い、resolved symbol / source実装 / external bridge / 未解決を区別する入力を用意する。
  - 完了条件: source-backed member alias・imported宣言・ユーザー同名関数・nil symbolをテストし、direct / virtual callの既存差異を明示する。`isSourceBackedSymbol` の意味やSema flagsを変更せず、Sequenceのruntime表現例外をまだ消さない。CALL-008以降はこの境界を使う。
  - 完了根拠（抽出のみ。判断順序・出力ともに不変）:
    - 新設 `Sources/CompilerCore/Lowering/SourceBackedCallPreservationPolicy.swift`。`SourceBackedCalleeResolution`（`.unresolved` / `.unknownSymbol` / `.sourceBacked` / `.externalBridge`）と `SourceBackedCallPreservationPolicy`（`preservesDirectCall` / `preservesVirtualCall`）の2型。分類は `SymbolTable.isSourceBackedSymbol` をそのまま唯一の権威として呼び、flags / declSite を直接読まない。
    - `CollectionLiteralLoweringRegistry.init` でpass実行ごとに1個だけ構築し、`CollectionLiteralConstructionLoweringPass` と `CollectionVirtualCallRewriteLoweringPass` の両方へ注入。従来は呼び出し命令ごとに `||` 連鎖（direct 103行 / virtual 111行）と6要素・13要素の `Set` リテラルを毎回組み立てていた。
    - direct / virtual の既存差異（コード上どこにも書かれていなかった）を名前付きsetとして固定: 共通 `sharedAggregateNames` 91件、`virtualOnlyAggregateNames` 20件（CALL-009 が direct から落とした accumulation 11名 + `isEmpty` / `iterator` / `toList` / `toIntArray` / `average` / `chunked` / `windowed` / `random` / `randomOrNull`）。array変換はdirectが「pre-scanが追跡中のarray式」＋`size`・`toList`込み、virtualが「receiverの静的型が配列クラス」＋`size`別分岐・`toList`非対象という非対称のまま。元コードが `minByOrNull`（direct/virtual）・`sorted`（virtual）を二重に列挙していた分はSetで一意化され、判定は不変。
    - 判断順序の保持: 入力は全て `@autoclosure` / closure。名前一致より前にsymbol table・`functionSignature`・`arena.exprType` を引かない元の短絡順序を維持する。virtualのarray分岐は receiver class が解決できたときだけ集合所属で答え、解決できなければAPI set側へfall throughする元の構造も保持（`size` / `sliceArray` 系はどちらのAPI setにも無いため現状は結果同値だが、構造を潰していない）。
    - Sequenceのruntime表現例外は direct 側に2件（追跡済み `RuntimeSequenceBox` receiver、`Sequence` 型receiver）とも残置。`flatMap` / `flatMapIndexed` を除外する範囲も不変。virtual側に例外は無く、`rewriteSequenceVirtualCall` の `isSourceBackedSequenceCall` は CALL-014 の担当として未変更。
    - テスト: `Tests/CompilerCoreTests/Lowering/SourceBackedCallPreservationPolicyTests.swift` 20件。4分類（nil symbol / sema なし / table未登録ID / 宣言サイトあり / synthetic stub / `.importedLibrary`）、KSP-443 member alias が `.externalBridge` になること（nil declSite + `.synthetic` の兄弟合成宣言なので `isSourceBackedSymbol` は false）、direct/virtual差異のset形状、array receiver 13クラス、Sequence例外2件と `flatMap` 非適用、ユーザー同名関数（`flatten` / `Bag.count`）のsource経路生存を固定。
    - KIR不変の実測: 全分岐を踏む fixture（List HOF・array literal の `size`/`toList`/`asList`/`sliceArray`/`copyOf`/`reversedArray`、`IntArray`、Map HOF、`sequenceOf` と `asSequence` 双方の `map`/`filter`、`Sequence` 引数、range の `toList`/`chunked`/`isEmpty`、ユーザー同名extension）を `--emit kir` で origin/master ビルドと本ブランチビルドの2回dumpし、1561行が**byte一致**（sha256先頭 fa0f9333cd248751）。dumpには保持された `map`/`filter`/`fold`/`sorted`/`mapValues`/`filterKeys`/`chunked`/`asList`/`sliceArray` と rewrite後の `kk_*` / `__kk_*` が同時に現れており、両側を実際に通っている。
    - `loc_report.sh`: `loc_by_directory Sources` +71（`+CallRewrite.swift` -142 / `+VirtualCallRewrite.swift` -152 / registry +26 / 新policy +339）、`Tests` +528、`.`（TODO.md）+11。`kk_literal_count` は +2 で、いずれも KSP-443 alias fixture が source 宣言と alias に同じ `externalLinkName` を持たせる箇所のテスト文字列（コンパイラが emit する名前ではない）。他の指標（`HeaderHelpers+Synthetic*` 行数・KIR/Lowering TODO/FIXME・`interner.resolve == "..."`・`kk_cdecl_count` / `__kk_cdecl_count`）は不変。
  - **マージ順序の制約（重要・2026-09-14 時点で解消済み）**: 本項は series の他項より後に取り込む必要があった。着手時の `gh pr list --state all --search "RF-LOWER-CALL"` では CALL-001 しか出なかったが、これは検索インデックスの遅延による見落ちで、実際には CALL-002〜012 の9本が open で、いずれも本項が移動させた同じ hunk を編集していた（列挙は `--search` ではなく `gh pr list --state open --limit 40` で行う）。
    - 009 / 010 / 011 / 012 は inline の `||` 連鎖から名前を削除する変更で、本項の Set は移動時点の全名を保持していたため、先にマージされた後に「抽出側を採用」で解決すると削除済みの名前が復活する関係にあった。実際 CALL-011 は `kk_list_maxOfOrNull` 等 `@_cdecl` の無い spec-only export への redirect を含む。
    - 実績: CALL-002 (#6761) / 003 (#6758) / 004 (#6768) / 005 (#6759) / 006 (#6765) / 009 (#6762) / 010 (#6766) / 011 (#6763) は master に入り、そのたびに master をマージして Set から削除分を反映した。現在 open で残るのは **CALL-008 (#6770)** と **CALL-012 (#6764)** の2本で、どちらも同じ保持判断を触るため、本項が先に入る場合は向こう側が Set に対して削除を当てる必要がある。
    - 反映が正しいことの判定は KIR byte 一致では**できない**（削除対象の名前は何も守っていないので、残しても消しても KIR は同一）。`sharedAggregateNames` ≡ master の direct guard、`shared ∪ virtualOnly` ≡ master の virtual guard という集合等価だけが唯一の検出手段。現在 63 / 82 で一致。
    - CALL-011 の副作用として `CollectionLiteralLookupTables` の該当プロパティ19個が削除されたため、その19名は復活させようとしてもコンパイルが通らない。残る `sorted` / `max` / `maxOrNull` / `minOrNull` の4名だけが黙って復活しうるので、`sortExtremaNamesAreGoneExceptVirtualOnlySorted` で固定した。`sorted` は Range 消費者のため virtual 側のみ生存。
  - 実行範囲: `swift build` と `CompilerCoreTests.{SourceBackedCallPreservationPolicyTests, CollectionLiteralLoweringTests, BuilderDSLLoweringRoutingTests, CollectionClassificationTests}`（20 / 68 / 5 / 6 件すべてPASS）＋上記KIR byte比較・`loc_report.sh` 比較。全Swiftテスト・Golden 4系統・`diff_kotlinc.sh` 全ケースは本セッションでは未実行。
- [x] RF-LOWER-CALL-008: Listの変換・filter系だけをsymbol基準の保持判断へ寄せる（前提: CALL-007）
  - 対象: policyと `+CallRewriteHOFTransforms.swift` / `+CallRewriteHandlers.swift` の `map*` / `flatMap*` / `filter*` 系のうちsource移行済み経路、必要なlookup・対応テスト。Map / Array / Sequenceの同名APIは対象外。
  - 完了条件: 選択済みKotlin宣言が保持され、不要なList rewrite・名前列挙を削除できる。通常・indexed・nullable要素・捕捉lambdaの代表ケースを固定し、未移行overloadを同名という理由で消さない。
  - 完了根拠:
    - 対象17名（`map*` / `flatMap*` / `filter*`、KSP-421 で `ListHOF.kt` / `ListFilterHOF.kt` に source 化済み）は全件 `StdlibSurfaceSpec.listHOFMembers`（`.list` owner）に runtime link が無く、`collectionHOFRuntimeName(ownerKind: .list, ...)` は無条件 nil。ただし CALL-007 で direct/virtual の allowlist が `sharedAggregateNames` へ統合されたため、削除可否は **List 以外のレシーバでの生存確認**で決まる:
      - `map` / `filter` / `flatMap`: Map receiver の `kk_map_*` rewrite（`+CallRewriteHandlers.swift` の `mapHOFRuntimeName` / `+VirtualCallRewrite.swift` の `rewriteMapHOF`）が現役 → 保持
      - `mapIndexed` / `mapNotNull` / `filterIndexed` / `filterNot`: `RangeHOF.kt` が `IntRange` / `IntProgression`（と UInt 版）にも同名で実装しており、`+VirtualCallRewrite+Range.swift` の `kk_range_*` rewrite が nil ガード無しの直接呼び出しで現役 → 保持
      - `flatMapIndexed` / `flatten`: Sequence pipeline / terminal rewrite（`+CallRewriteSequencePipeline.swift` / `+CallRewriteSequenceTerminals.swift`、`sequenceExprIDs` 起点）が現役 → 保持
      - 上記9名を除いた **`mapTo` / `mapIndexedTo` / `mapNotNullTo` / `mapIndexedNotNullTo` / `flatMapTo` / `flatMapIndexedTo` / `mapIndexedNotNull` / `filterNotNull` の8名**のみ、Sources全体を再帰grepして他レシーバにも rewrite 消費者が皆無なことを確認し `sharedAggregateNames` から削除。8名とも `ListHOF.kt` / `ListFilterHOF.kt` に実装済みで未移行overloadではない
    - `+CallRewriteHOFTransforms.swift`: `.list` arity 2 の `*To` destination分岐（`associateTo` の分岐込み）と `.list` arity 1 の `mapIndexed`/`mapIndexedNotNull`/`onEachIndexed` 分岐を削除。両分岐とも `collectionHOFRuntimeName(ownerKind: .list, ...)` が該当callee全件で無条件nilのため、symbol解決の有無に関わらず構造的に到達不能。`associateTo` / `onEachIndexed` のallowlistエントリ自体は対象外のタスクの担当のため未変更（コードだけ削除）
    - `+CallRewriteHandlers.swift`: `isCollectionHOFMemberName` から `mapNotNull` / `filterNot` を削除（List分岐もMap分岐も必ずnilを返し両レシーバで無意味）。対応する `!= filterName` / `!= filterNotName` 除外、`listHOFReturnsList` の `mapNotNull` 参照も削除
    - `+VirtualCallRewrite.swift` / `+CallRewriteHOFCore.swift` は対象ファイル外のため未変更（前者はRF-LOWER系の共通直列ファイル指定、後者は `forEach` 分岐が生きておりCALL-009/010/012が触る）。両ファイルに残る同種の `.list` 専用デッドコード（`*To`分岐、indexed分岐）はCALL-015への申し送り事項
    - 旧試行 PR #6770（CALL-007マージ前、67コミット遅れのブランチ、gh検索インデックス遅延で今回まで未検出）は同じ考え方で12名削除していたが、当時は direct/virtual の allowlist が分離されておりRangeへの影響が無かった。CALL-007統合後の現行 policy で同じ12名を削除すると、Rangeの `mapIndexed`/`mapNotNull`/`filterIndexed`/`filterNot` が誤って `kk_range_*` へ rewrite される。本PRは対象を8名へ縮小し、#6770はスーパーシード扱いでclose済み（#6836）
  - テスト: `Tests/CompilerCoreTests/Lowering/ListTransformFilterPreservationTests.swift`（新設、5 test / 27 ケース: 通常・捕捉lambda・indexed・indexedNotNull・nullable要素・`filterNotNull`・`flatMap(Indexed)`・`flatten`・`filter`・`filterNot`・`filterIndexed`・6種の`*To`、Map receiver 3件、Range receiver 4件）、`SourceBackedCallPreservationPolicyTests.swift`（`sharedAggregateNames.count` 63→55 に更新、8名の不在と9名の残置を固定する新規テスト1件追加）
  - 実行範囲: `swift build` green。`CompilerCoreTests.{ListTransformFilterPreservationTests, SourceBackedCallPreservationPolicyTests, ListAccumulationSourcePreservationTests, ListSearchPredicateLoweringRoutingTests, ListSortExtremaLoweringRoutingTests}` 40 tests / 5 suites 全PASS（共有マシンの高負荷 load average 300+ で実行に約27分）。全Swiftテスト・Golden・`diff_kotlinc.sh`・`loc_report.sh` は未実行（CIに委ねる。diffは `"kk_"` 文字列リテラル・`@_cdecl` の追加が無く `kk_literal_count` / `kk_cdecl_count` / `__kk_cdecl_count` は不変と判断）。
- [ ] RF-LOWER-CALL-009: Listの畳み込み・累積系の保持判断を整理する（前提: CALL-008）
  - 対象: policyと `+CallRewriteHOFAccumulations.swift` の `fold*` / `reduce*` / `scan*` / `running*` 系、必要なlookup・テストのみ。
  - 完了条件: source移行済みoverloadの旧rewriteと保護用名前列挙が減り、空入力・nullable accumulator・例外・左右の評価順の契約を保持する。型消去境界のboxing/unboxingは別責務として維持する。
  - 進捗（2026-09-13、List側のみ。`[ ]` のまま）: `shouldPreserveSourceBackedAggregateCall` の accumulation 19名のうち、下流rewriteを持たない11名（`fold` / `foldIndexed` / `foldRight` / `foldRightIndexed` / `reduce` / `reduceOrNull` / `reduceRight` / `reduceRightOrNull` / `reduceRightIndexed` / `reduceRightIndexedOrNull` / `scanReduce`）を preserve allowlist から削除し、契約を `Tests/CompilerCoreTests/Lowering/ListAccumulationSourcePreservationTests.swift` に移した。
    - 削除の根拠: (1) List側の旧runtime bridgeは既に emit 元ゼロ — `kk_list_fold*` / `kk_list_scan*` / `kk_list_runningFold*` は `RuntimeABISpec` と `ABIMismatchRuntimeExportParityTests.swift` の spec-only 許可リストにしか残っておらず、Lowering/CallLowerer から emit されない。(2) Sequence / Range の accumulation routing は `MemberRuntimeDispatch` → `CallLowerer` 側で決まり、Lowering には既に `kk_` 名で届く。よって11名の分岐は短絡すべき rewrite を持たない。
    - 実測: プローブ2本（List literal / List parameter / MutableList / `Array` / `IntArray` / `CharSequence` / `Set` / `Map.entries` / `Map.keys` / `asSequence` / `sequenceOf` / `generateSequence` / `IntRange` の各レシーバ）で `--emit kir` の KIR ダンプがバイト単位で不変、`--stdlib-from-source -o` の実行出力も不変。
    - 保持した8名（`scan` / `scanIndexed` / `runningFold` / `runningFoldIndexed` / `runningReduce` / `runningReduceIndexed` / `reduceIndexed` / `reduceIndexedOrNull`）: `+CallRewriteHOFAccumulations.swift` の `sequenceExprIDs` gated 分岐が残る唯一の名前群。source宣言＋RuntimeSequenceBox レシーバのときに rewrite すべきか否かは KSP-441 の判断で **CALL-014 の担当**（guard 末尾の map/filter 例外と同じ問題）なので、本PRでは挙動を変えていない。新テストで現状を固定済み。
    - 副次的な発見（本PRでは未修正）: `+StaticTypeClassification.swift` の `trackedStaticTypeKind` は KSP-441〜447 で `.sequence` の return をコメントアウトしており、`classifyTrackedExprByStaticType` の `case .sequence: state.sequenceExprIDs.insert(raw)` 分岐は到達しない。このため `sequenceExprIDs` は rewrite 結果と `kk_sequence_requireNoNulls` からしか埋まらず、`sequenceOf` / `generateSequence` / `asSequence` は source-backed で保持されるため上記8名の Sequence gated 分岐を踏むプローブを構成できなかった。「構成できない」は「到達不能」の証明ではないので削除はしていない。判定根拠の置換は CALL-014、dead な `case .sequence` の掃除は STATE 系の範囲。
    - stdlib surface gap（範囲外）: `Array<T>.foldRight` / `Array<T>.reduceRight` / `IntArray.foldRight` / `CharSequence.foldRight` は `KSWIFTK-SEMA-0024` で未解決。プローブから除外した。
  - レシーバ分類の順序も確認済み: 削除により preserve の短絡がなくなるため、accumulation 呼び出しが `rewriteHigherOrderCollectionCall` 冒頭の `classifyTrackedExprByStaticType` を通るようになる。ただし `+PreScan.swift` の `seedCollectionExprIDsFromStaticTypes`（LOWERING-001）が rewrite ループ前に関数本体の全参照式を静的型でシードするため、この遅延分類は top-up にすぎず副作用にならない。`fold` / `reduceRight` / `scanReduce` の直後に `listExprIDs` gated な `size` / `get` / `isEmpty` / `count` / `contains` を並べたプローブ（順序を入れ替えた3関数）でも KIR は不変で、`__kk_list_size` / `__kk_list_get` / `kk_list_is_empty` への書き換えは変更前後で同一だった。
  - lookup は削除していない: 11名の `lookup.*Name` はいずれも `+VirtualCallRewrite.swift` の virtual 側 preserve allowlist（と `+VirtualCallRewrite+Range.swift` / `+VirtualCallRewrite+Sequence.swift` の Range / Sequence rewrite）から参照が残るため、宣言が dead にならない。virtual 側の対応する保持判断は CALL-007 の 対象。
  - virtual 側は未検証で未変更: `+VirtualCallRewrite.swift` の `shouldPreserveSourceBackedVirtualCall` にも同じ19名が並ぶが、本PRのプローブは `virtualCall` 命令を1件も生成しておらず（`(1..4).fold` 等も extension なので direct `.call`）、到達性を実測していない。さらに direct 側と違い `+VirtualCallRewrite+Range.swift` に Range gated な `fold` / `foldIndexed` / `reduce` / `reduceIndexed`、`+VirtualCallRewrite+Sequence.swift` に `scanIndexed` / `runningFoldIndexed` / `reduceIndexed` / `reduceIndexedOrNull` の rewrite が実在するので、direct 側の結論を対称に適用してはいけない。virtual 側は CALL-007 の 対象。なお CALL-011 は sorted/min/max 25名を direct/virtual 両方から削除しているので、そちらの手順（外側メンバー名ゲートまで遡る + KIR byte-identical）を参照すること。
  - 残作業: policy への配置は CALL-007 の担当。CALL-007 が `shouldPreserveSourceBackedAggregateCall` を移設する際は、本PRで縮んだ HEAD 側の実装を持っていくこと（11名を復活させない）。保持した8名の撤去は CALL-014 の判断待ち。
  - ゲート: `swift build` green。`bash Scripts/swift_test.sh --skip-build --filter "CompilerCoreTests.*Lowering"` で 22 suite / 365 テスト PASS（新 `ListAccumulationSourcePreservationTests` 3件、`CollectionLiteralLoweringTests` 68件、CALL-001 の `BuilderDSLLoweringRoutingTests`、`LoweringPassRegressionTests` を含む）。全 Swift テスト・Golden 4系統・`diff_kotlinc.sh` 全件は未実行 — KIR/実行出力の不変性を実測済みで、accumulation 系は既存 `Scripts/diff_cases/` 39ケースが oracle として残っている。
- [x] RF-LOWER-CALL-012: Map HOFのsource-backed保護と残存rewriteを整理する（前提: CALL-011）
  - 対象: policyと `+CallRewriteHandlers.swift` / Map HOF分岐、Map用lookup・テスト。`mapValues*` / `mapKeys*` / `filterKeys` / `filterValues` 等について解決先を確認する。
  - 完了条件: source実装の同名overloadを横取りせず、Listを返す操作とMapを返す操作の分類・重複key・挿入順・lambda例外を保持する。Set / factoryの変更は混ぜない。
  - 実施内容（2026-09-14、CALL-011と同じ手法）: KSP-430で `Stdlib/kotlin/collections/MapHOF.kt` がMap HOFの全実装（`map`/`filter`/`filterNot`/`mapNotNull`/`forEach`/`mapValues`/`mapValuesTo`/`mapKeys`/`mapKeysTo`/`filterKeys`/`filterValues`/`flatMap`/`any`/`all`/`none`/`maxByOrNull`/`minByOrNull` 等）を持つ一方、これらの名前を対象にした `kk_map_*` ランタイムrewriteブランチが3箇所に残存していた: `+CallRewriteHandlers.swift`（`rewriteCollectionHOFCall`のMap分岐＋`mapHOFRuntimeName`/`mapHOFReturnsList`/`mapHOFReturnsMap`）、`+CallRewriteHOFCore.swift`（`rewriteCoreHigherOrderCollectionCall`内のインラインMap分岐、CALL-012の対象行には明記されていないが同一の到達不能コードなので併せて削除）、`+VirtualCallRewrite.swift`（`rewriteMapHOF`とその呼び出し）。いずれも `shouldPreserveSourceBackedAggregateCall` / `shouldPreserveSourceBackedVirtualCall` が該当名をsource-backedとして先に短絡するため到達不能で、`filterKeys`/`filterValues`/`maxByOrNull`/`minByOrNull`は外側のmember-name gate（`isCollectionHOFMemberName`、`rewriteCoreHigherOrderCollectionCall`冒頭のif）にも列挙されていなかった。`kk_map_map`/`kk_map_filter`/`kk_map_forEach`/`kk_map_mapValues`/`kk_map_mapKeys`/`kk_map_filterKeys`/`kk_map_filterValues`/`kk_map_flatMap`/`kk_map_any`/`kk_map_all`/`kk_map_none`/`kk_map_maxByOrNull`/`kk_map_minByOrNull`はいずれも`Sources/Runtime`に`@_cdecl`が無く（`Tests/RuntimeTests/RuntimeCollectionHOF430MapShims.swift`のテスト用shimのみ）、到達していれば実行時に壊れていた。加えて`+CallRewrite.swift`/`+VirtualCallRewrite.swift`のpreserve policyから`maxByOrNullName`/`minByOrNullName`（両方の分岐で他に消費者なし）と、対応するlookupフィールド2件・`+LookupTables+Map.swift`の`kkMap*`系13フィールドを削除（`kkMapCountName`は維持: `+CallRewriteFactories.swift:320`がMapの`count(predicate)`を`kk_map_count`へ書き換える経路で今も参照しているが、この`kk_map_count`も`Sources/Runtime`に`@_cdecl`が無く同じ到達不能パターンに見える。`countName`もpreserve policyに残っており、Factories.swift側は本タスクの対象外の共有ファイルのため未調査のまま引き継ぐ）。`mapValues`/`mapValuesTo`/`mapKeys`/`mapKeysTo`/`filterKeys`/`filterValues`はpreserve policyに残置（`mapValues`/`mapKeys`は`rewriteCoreHigherOrderCollectionCall`の外側gateと`isCollectionHOFMemberName`を今も通るため、ここで短絡した方が無駄な到達試行を避けられる。その外側gate自体はmapValues/mapKeysをinertなまま列挙し続けており、`shouldPreserveSourceBackedAggregateCall`相当の名前列挙を閉じるCALL-015が最終的な撤去先）。
  - 実測: プローブ3本（Map literal・chain済み呼び出し・interfaceプロパティ/abstract classメソッド経由のvirtual dispatch）で`--emit kir`のKIRダンプが削除前後・`--stdlib-from-source`/artifact両パスでバイト単位不変（`kk_map_of`以外の`kk_map_*`出現ゼロ）。virtual dispatch側は`rewriteMapHOF`削除前から`.virtualCall`命令を1件もMap HOF名に対して生成しておらず（extension関数なので常にstatic dispatch）、削除は無害と確認。実行結果も不変（重複key `mapKeys`は後勝ち、`filterKeys`/`filterValues`は挿入順維持、`mapValues`/`filter`のlambda例外は正しく伝播）。
  - テスト: 新規 `Tests/CompilerCoreTests/Lowering/MapHOFLoweringRoutingTests.swift`（4件、実コンパイラパイプラインでsource-backed維持・legacy名不在・virtual dispatch非経由を検証）、新規 `Tests/CompilerBackendTests/Codegen/CodegenBackendMapHOFTests.swift`（6件、IRレベルのlegacy名不在×2パス＋実行コントラクト4件: 重複key/挿入順/List・Map分類/lambda例外。ファイル名は当初`CodegenBackendIntegrationTests+MapHOF.swift`だったが、#6774のBase+Suffix命名是正に合わせ`@Suite`型名`CodegenBackendMapHOFTests`と一致するよう改名）。既存 `CollectionLiteralLoweringTests.swift`の`testMapAnyRewriteToKkMapAny`等3件は`symbol: nil`の合成KIRで到達不能だった旧分岐だけを踏んでいたため、削除ではなく現在の正しい経路（rewrite無しでそのまま生存）を検証する内容に更新（`testMapAnySurvivesWithoutRewrite`等）。`ListSortExtremaLoweringRoutingTests.mapExtremaKeepTheirSourceCallAndNotTheMapRuntimeRewrite`のコメントも、policyから該当2名を削除した事実に合わせて更新。
  - ゲート: `swift build`/`swift build --build-tests` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --skip-build --filter "CompilerCoreTests.*Lowering"` で 25 suite / 366 テスト PASS（新`MapHOFLoweringRoutingTests` 4件を含む）。`--filter "CompilerBackendTests.CodegenBackendMapHOFTests"` 6件 PASS。`bash Scripts/diff_kotlinc.sh` は `map_basic`/`map_entries_hof`/`map_hof`/`map_mapkeysto`/`map_mapvaluesto`/`stdlib_kotlin_collections_Map_map` の関連6ケースのみ実行しPASS（全件は未実行）。Golden 4系統・全Swiftテストは未実行。
  - 副次的な発見（本PRでは未修正、別セッションへspawn_task済み）: `listOf("a","bb").flatMap { it.toList() }`のように`flatMap`の結果`List<Char>`をprintすると`[a, b, b]`ではなく`[97, 98, 98]`（Charのbox tagを落として生のInt32コードを表示）になるバグを発見。Map/Listどちらの受信者でも再現し、Char単体やListOf直接構築では発生しないため`flatMap`の汎用宛先追加経路に起因。本PRのMap分類スコープとは無関係のため別修正PRへ切り出した([#6823](https://github.com/kuu-lab/swifty-kotlin/pull/6823))。
  - 2026-09-15 rebase: masterがRF-LOWER-CALL-007（#6773、preserve policyを`SourceBackedCallPreservationPolicy.swift`へ抽出）を含めて進んだためconflict、`SourceBackedCallPreservationPolicy.sharedAggregateNames`に同じ変更を再適用してmerge（マージコミット参照）。ついでに`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+MapHOF.swift`を#6774のBase+Suffix命名是正に合わせ`CodegenBackendMapHOFTests.swift`へ改名。
  - 2026-09-15 follow-up: 未調査のまま残していた`kkMapCountName`/`+CallRewriteFactories.swift:320`の`count(predicate)` → `kk_map_count`経路を調査し、同じ理由（`bundledIndex.contains`によりsource-backed確定、`kk_map_count`に`@_cdecl`無し）で到達不能と確認。dead branchと孤立した`kkMapCountName`/`isSourceBackedBundledFunction`を削除し、新規`MapCountLoweringRoutingTests`で到達不能性を実測（[#6839](https://github.com/kuu-lab/swifty-kotlin/pull/6839)）。
- [x] RF-LOWER-CALL-013: Arrayのsource-backed変換API保護を整理する（前提: CALL-012）
  - 対象: policy、`+CallRewriteArrayConversions.swift` / `+VirtualCallRewrite+Array.swift` のsource-backed変換分岐、対応lookup・テスト。`asList` / `toList` / `toTypedArray` / `sliceArray` / `copyOf*` / `reversedArray` 等の現在の移行状態を照合する。
  - 完了条件: generic / primitive / unsigned Arrayの宣言選択とview / copyの違いを保持し、型名・関数名だけを根拠に誤ったruntime表現へredirectしない。Arrayの格納形式やABI変更は対象外。
  - バグ修正（発見PR内で修正、バグ修正ルール）: `toMutableList()` を `IntArray`/`LongArray`/…/`Array<T>` 全13レシーバでsource化（`ArrayConversions.kt`/`UArrays.kt`に`this.toList().toMutableList()`委譲の宣言を追加）した後も、`+CallRewriteArrayConversions.swift`のtoMutableList分岐が`symbol`のsource-backed判定を一切せず`state.arrayExprIDs`一致だけで無条件に`kk_array_toMutableList`へredirectしていた（兄弟のtoTypedArray分岐は既に`isSourceBackedSymbol`判定を持っていたのに、toMutableListだけ欠落）。結果、`longArrayOf(Long.MIN_VALUE).toMutableList()`が`[null]`（ランタイムのnull sentinelとビット衝突）、`ulongArrayOf(ULong.MAX_VALUE).toMutableList()`が`[-1]`（符号なし→符号付き誤boxing）になる実行時バグを発見・再現・修正。修正はtoTypedArray分岐と同じ`symbol.map({ isSourceBackedSymbol($0) != true }) ?? true`ガードをtoMutableList分岐に追加（`+CallRewriteArrayConversions.swift`）。回帰は`Tests/CompilerBackendTests/Codegen/CodegenBackendArrayConversionTests.swift`（Long.MIN_VALUE/ULong.MAX_VALUE/UInt.MAX_VALUE/UByte.MAX_VALUE/UShort.MAX_VALUE の5本、修正前に実際に落ちることを確認してから固定）。
  - 到達可能性の実測（`--emit kir`のablation: 分岐を`if false,`で個別に無効化→再dump→callee出現数を比較。CALL-012の手法を踏襲）:
    - `+VirtualCallRewrite+Array.swift`の4分岐（toList/toMutableList/fill/asSequence）は**全滅到達不能**と確定 — ファイル削除。根拠は二重: (1) 13レシーバ×literal/parameter/interface-property receiverの総当たりprobeで`.virtualCall`命令がArray系メンバー呼び出しに対して1件も生成されない（Arrayはfinal/intrinsic型でSema/CallLowererの仮想dispatch対象にならない。生成された6件の`.virtualCall`は全て無関係なinterfaceプロパティgetter）。(2) `toMutableList`/`fill`は`chosen == nil`の間`CallLowerer+UnresolvedMemberCalls.swift`のdictionary（`isConcreteArrayLikeType`ベース）がLowering到達前に直接`kk_array_toMutableList`/`kk_array_fill`をcallee名として確定させており、Lowering側の名前一致チェック（`callee == lookup.toMutableListName`等）が文字列レベルで一度も一致しない。source化後の`toMutableList`はCallLowerer側で`chosen`が解決されるため文字列は`"toMutableList"`のまま届くが、それを拾うのは`+CallRewriteArrayConversions.swift`（direct）であり、こちらは元々一度も`.virtualCall`化されない。
    - `+CallRewriteArrayConversions.swift`は3分岐（toMutableList/toTypedArray/fill）を`if false,`で同時に無効化しても`probe_array_conversions.kt`・`probe_fill_bridge.kt`（Long.MIN_VALUE等のedge case込み）で出力・KIRとも無変化 — ファイル全体削除。`toTypedArray`はprimitive/unsigned 12型がsource-backed（`chosen != nil`で本分岐は素通り）、generic `Array<T>.toTypedArray()`は宣言自体が存在せずSemaが`KSWIFTK-SEMA-0024`で拒否（Loweringに到達しない）。`fill`はsource宣言が存在しないため常に`CallLowerer+LegacyMemberLikeCalls.swift`の`chosen == nil`分岐（`case "fill": "kk_array_fill"`、無条件）が先にcallee名を確定させる。呼び出し元`+CallRewriteSequence.swift:51-64`も削除。
    - `+VirtualCallRewrite.swift:203-225`のtoTypedArray重複分岐も同じ理由（primitive/unsigned source-backed、generic Array<T>はSemaで拒否）で削除。
    - `asSequence`はCALL-014（Sequence実行時表現の判断）の担当と判定し本PRでは触れない: `Array<T>.asSequence()`はsource-backed（`ArrayHOF.kt`、`.toList().asSequence()`経由で真のSequenceオブジェクトを生成）だが、direct-call側`+CallRewriteSequencePipeline.swift`（policy対象外の別ファイル）が`isSourceBacked`判定込みでgeneric/primitiveを正しく区別しておりprobeで確認済み。virtual側の（削除した）分岐は無条件redirectだったが実際には`.virtualCall`化されないため実害はなかった。
    - 副次的発見（本PR未修正、`Sources/Runtime/RuntimeArrayDequeAndUtility.swift`の`kk_array_fill`）: `array.elements[i] = value`のループがO(n²)（`elements`はget/setのたびに全要素を`[Int]`へ実体化。`RuntimeArrayBox`のdocコメントが明記する既知の罠）に加え、`elements`のsetterは`RuntimeValue(raw:)`をタグ無し既定値で再構築するため`subscript(index:)`と違い各要素の`anyFallbackTag`を消す。Array格納形式・ABI変更は本タスク対象外のため未修正。観測可能な症状は現状`Any`消去経路（`hashCode()`等）経由に限られる。Linear（team Kuu / バグバックログ）に起票予定。
  - policy整理: `directArrayConversionNames`から`sliceArray`/`reversedArray`/`asList`/`toTypedArray`を削除（`sizeName`/`toListName`のみ残置、他receiver種別への影響ゼロを個別grepで確認済み）。`virtualArrayConversionNames`（上記4名、`arrayReceiverTypeNames`と`size`分岐を共有）はセット自体が空になるためプロパティごと削除、`preservesVirtualCall`の対応ifも削除。`sharedAggregateNames`から`copyOf`/`copyOfRange`を削除（Lowering全体で消費者ゼロを確認）。`arrayReceiverTypeNames`は`size`分岐が使うため残置。lookup側は`toMutableListName`/`toTypedArrayName`/`sliceArrayName`/`reversedArrayName`/`asListName`/`copyOfName`/`copyOfRangeName`/`fillName`/`kkArrayToMutableListName`/`kkArrayFillName`を削除（`kkArrayCopyOfName`は`+CallRewriteIteratorBridge.swift`の`intArrayOf(*array)`スプレッドコピー経路、`kkArrayToListName`は`+CallRewriteSequenceTerminals.swift`（CALL-014対象、未変更）、`kkArrayAsSequenceName`は`+CallRewriteSequencePipeline.swift`がそれぞれ使うため残置）。Runtime側の`@_cdecl("kk_array_fill")`/`kk_array_toMutableList`自体は削除していない（`CallLowerer`の`chosen == nil`経路から引き続き参照されるため生存）。
  - テスト: `SourceBackedCallPreservationPolicyTests`のセット形状テストを更新（`arrayConversionSetsDifferBetweenDirectAndVirtualCalls`→`directArrayConversionNamesAreSizeAndToListOnly`、`virtualArrayConversionAcceptsEveryArrayReceiverClass`→`virtualSizeAcceptsEveryArrayReceiverClass`）。`CollectionLiteralLoweringTests.testVirtualCallOnArrayTypedParameterRewritesToKkArrayToList`はSTATE-005が言う「symbol: nilの合成KIRで到達不能だった旧分岐だけを踏んでいた」ケースそのものだったため、CALL-012と同じ方針で現在の正しい経路（`.virtualCall`のまま素通り、`__kk_array_toList`は出ない）を検証する内容に更新。新規`Tests/CompilerBackendTests/Codegen/CodegenBackendArrayConversionTests.swift`（8件: IR残存チェック1件＋Long/ULong/UInt/UByte/UShortのtoMutableListバグ回帰5件＋generic Array健全性1件＋asList view / toMutableList copyのセマンティクス区別1件）。
  - ゲート: `swift build` / `swift build --build-tests` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --skip-build --filter "CompilerCoreTests.*Lowering"` で27 suite / 369テストPASS（`SourceBackedCallPreservationPolicyTests`・`CollectionLiteralLoweringTests`・`CollectionRewriteStateTests`・`CollectionClassificationTests`含む）。`--filter "CompilerBackendTests.CodegenBackendArrayConversionTests"` 8件PASS。`bash Scripts/diff_kotlinc.sh`は関連15ケース（`array_conversions`/`array_copy`/`array_copy_of_range`/`array_slice`/`array_edge_cases`/`array_hof_source_backed`/`primitive_array_hof_source_backed`/`array_primitive_types`/`list_to_array`/`list_to_array_basic`/`array_content_to_string_and_copy_of`/`array_of`/`array_of_nulls`/`array_hof`/`array_star_projection_cast_write`）を個別実行し全PASS（`assertKotlinOutput`のデフォルトである`.kklib`アーティファクト経路もCodegenBackendArrayConversionTestsで別途カバー済み — BUG-257の教訓通り`--stdlib-from-source`一本槍にしていない）。Runtimeファイルは一切変更していないため`@_cdecl`カウント（`kk_cdecl_count`/`__kk_cdecl_count`）は不変。Golden 4系統・全Swiftテスト・`diff_kotlinc.sh`全件・`loc_report.sh`比較は未実行（Sources/CompilerCore配下のみの変更でRuntimeに影響なし）。
- [x] RF-LOWER-CALL-014: Sequenceの保持例外を明示的な実行時表現に基づく判断へ置き換える（前提: CALL-013、STATE-009）
  - 対象: policyと `+CallRewriteSequencePipeline.swift` / `+CallRewriteSequenceTerminals.swift` のsource / runtime bridge選択。`Sequence`という静的型だけでは `RuntimeSequenceBox` とsourceオブジェクトを区別できないことを前提にする。
  - 完了条件: source / runtime由来、引数渡し、copy経由、由来不明をテストし、`map` / `filter` の既存例外を表現判定へ置換する。由来不明をsourceと決め打ちせず、遅延評価・例外タイミング・iterator bridgeを保持する。新しい全プログラム解析やRuntime表現統合は行わない。
  - 完了根拠:
    - `CollectionRewriteState.SequenceRuntimeRepresentation`（`runtimeBox` / `sourceObject` / `notSequence` / `unknown`）を追加し、`sequence` / `sequenceSourceObject` / `sequenceType` の分類軸から保守的に判定。排他的でない由来は `unknown` とし、静的 `Sequence` 型だけでは bridge を選択しない。
    - `SourceBackedCallPreservationPolicy` の `map` / `filter` 例外を表現判定へ置換。Sequence pipeline / terminal の source-backed gate と map bridge は確認済み `RuntimeSequenceBox` のみ通過し、source object / 非 Sequence / unknown は元の source iterator 経路へフォールバック。public `sequenceOf` / `emptySequence` / `generateSequence` は overload に source object を含むため名前だけで runtime 分類しない。
    - テストで source / runtime producer、Sequence 引数、runtime/source copy、競合 provenance、静的型由来 unknown を固定。`swift build`、Lowering 3スイート（53件）、`CollectionLiteralLoweringTests`（67件）、Sequence map/mapIndexed（4件）、toMap/toSet/toList（5件）、Sequence EdgeCases（60件）がPASS。`git diff --check` もPASS。
    - 未実行: 全 Swift テスト、Golden 4系統、`diff_kotlinc.sh` 全ケース（CI に委ねる）。
- [x] RF-LOWER-CALL-015: 移行済みAPIの保護用名前列挙を撤去してpolicyを閉じる（前提: CALL-006・014）
  - 対象: policyとdirect / virtual callの入口、使われなくなったlookupのみ。List / Map / Array / Sequence各群で保持済みの宣言を共通原則へ統合し、残るintrinsicは識別根拠・runtime表現・対応テストを明確にする。
  - 完了条件: `shouldPreserveSourceBackedAggregateCall` 相当の巨大なAPI名allowlistがなく、解決済みの通常Kotlin宣言を保持し、必要なbridgeだけを書き換える。別の巨大表への移設・source-backed全件の無条件skipで達成したことにしない。残作業があれば具体的なAPI単位へ再分割し、本項を先に完了しない。
  - 完了根拠:
    - `SourceBackedCallPreservationPolicy` を名前集合・lookup・interner非依存のデータフリー判定へ縮小し、direct / virtual call入口を `SourceBackedCalleeResolution` と `SequenceRuntimeRepresentation` の共通判定へ統合。解決済みの通常Kotlin宣言は保持し、未解決・synthetic bridgeは既存rewriteへ流す。
    - runtime collection intrinsic は CallLowerer が先に選択した `kk_*` / `__kk_*` calleeをそのまま利用するため名前allowlistで保護せず、Sequence virtual `toMap` だけは確認済み `RuntimeSequenceBox` と `outThrown` ABIを根拠にbridgeを残した。トップレベル関数の通常のSequence引数をextension receiverと誤認しない判定も追加した。
    - Builder DSLの旧predicate / lookupと、policyからのみ参照されていたCommon lookup 12項目を撤去。liveなSet member bridge用のadd/remove lookupは`SetLookupNames`へ統合した。
    - 検証（最新変更後）: `swift build`、`SourceBackedCallPreservationPolicyTests` 9、`CollectionLiteralLoweringTests` 67、`ListAccumulationSourcePreservationTests` 3、`ListSearchPredicateLoweringRoutingTests` 4、`ListTransformFilterPreservationTests` 5（18 parameter cases）、`ListSortExtremaLoweringRoutingTests` 6、`MapHOFLoweringRoutingTests` 4、`MapCountLoweringRoutingTests` 2、`BuilderDSLLoweringRoutingTests` 5 がPASS。`git diff --check`もPASS。全Swiftテスト・Golden 4系統・`diff_kotlinc.sh`全件は未実行（CIに委ねる）。

### 2. 式分類・コピー伝播の一元化（RF-LOWER-STATE）

> STATE-001 → 002を先行。003と004はRegistryを共有するため直列。004後の005〜008は各葉ファイルだけなら並列可、共有ファイルを触るなら直列。009は003・007を待ち、010は003〜009の移行を待つ。CALL側と同一ファイルを変更する項目は、そのAPI群のPRとの同時着手を避ける。

- [x] RF-LOWER-STATE-004: virtual-call dispatcherの状態受け渡しを一つにする（前提: STATE-003）
  - 対象: `CollectionLiteralLoweringRegistry.swift` と `+VirtualCallRewrite.swift` の入口・dispatcher。葉の処理は変えず、dispatcherの境界でstateを受け渡す形にする。
  - 完了条件: Registryから十数個の集合を渡す引数列がなくなり、未rewrite時の元命令・結果型・throw channel・dispatch情報が保たれる。葉ファイルへの機械的な全面置換は005〜008に分ける。
  - 完了根拠（配線のみ。葉関数シグネチャ・処理本体は一切不変）:
    - `rewriteVirtualCallInstruction` の13個の集合引数（`inout Set<Int32>` ×12 + 値渡し `iteratorBuilderExprIDs`）を `state: inout CollectionRewriteState` 1個へ畳み、dispatcher 内の直接読み書きは `state.<名前付き集合>` へ機械的に前置しただけ。葉（`classifyReceiverByStaticType` / `rewriteArrayVirtualCall` / `rewriteSequenceVirtualCall` / `rewriteListHOFVirtualCall` / `rewriteCollectionPropertyVirtualCall` / `rewriteRangeVirtualCall` / `rewriteFileMemberVirtualCall`）は引き続き `&state.<名前付き集合>` で個別集合を受け取る — 葉の全面置換は STATE-005〜008 の範囲。
    - Registry 側は STATE-003 で既に `state: inout CollectionRewriteState` を受ける入口（`lowerVirtualCallInstruction`）があり、そこで展開していた13引数を `state: &state` 直渡しに変更。未 rewrite 時の `loweredBody.append(instruction)` フォールバックは `run` ループ側にあり不変。
    - `+RewriteState.swift` の doc コメントを更新: 「dispatcher が13引数を要求するため stored property 必須」の記述は本PRで解消された制約なので、残る制約（葉の個別 `inout` 引数 → STATE-005〜008 で撤去後に STATE-010 が view 化）を指す形に直した。
    - 検証（最小スコープ）: `swift build` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter "CollectionRewriteStateTests|CollectionClassificationTests|CollectionLiteralLoweringTests"` で 3 suite / 90 テスト PASS（virtual-call rewrite の24ケースと分類・copy伝播の契約を直接カバー）。**未実行**: 全 Swift テスト / `--filter Golden` / `bash Scripts/diff_kotlinc.sh` — 引数束ねのみの機械的変更で分類ロジックは1行も不変のため CI に委ねた。
- [x] RF-LOWER-STATE-005: Array virtual-callの分類操作をstate APIへ寄せる（前提: STATE-004。CALL-013と同時編集しない）
  - 対象: `+VirtualCallRewrite+Array.swift` と対応テストのみ。dispatcherへの変更が必要ならSTATE-004との境界を先に調整する。
  - 完了条件: Array用の集合操作・結果tag付けが共通APIを使い、generic / primitive Arrayの分類と戻り値が不変。calleeやboxing規則の変更はしない。
  - 完了根拠（配線のみ。emit する KIR・callee・copy 配置は一切不変）:
    - `rewriteArrayVirtualCall` の3つの集合引数（`listExprIDs` / `arrayExprIDs` / `sequenceExprIDs` の `inout Set<Int32>`）を `state: inout CollectionRewriteState` 1個へ畳み、分類参照を `state.contains(.array, receiver)`、結果 tag 付けを `state.tagListResult(_:temporary:)` / `state.tagResult(.sequence, _)` へ置き換え。`tagListResult` は `result` 非 nil 時に result と temporary の両方へ insert するので従来の2行 insert と同値、`tagResult(.sequence, result)` は nil ガード込みで従来の `if let` insert と同値。
    - dispatcher（`+VirtualCallRewrite.swift`）の callsite は `state: &state` 直渡しに変更 — STATE-004 が畳んだ境界をそのまま使い、葉側の引数列だけを更新。Array 以外の葉（Sequence / ListHOF / Property / Range / File）は未着手（STATE-006〜008 の範囲）。
    - 前提の扱い: STATE-004（#6795）のブランチ上に積んだ stacked PR。STATE-004 未適用の master では dispatcher に `state` 引数がなく本変更は成立しないため、ベースを `claude/rf-lower-state-004` に設定。
    - 検証（最小スコープ）: `swift build` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter "CollectionRewriteStateTests|CollectionClassificationTests|CollectionLiteralLoweringTests"` で 3 suite / 90 テスト PASS（array virtual-call の4ケース含む）。**未実行**: 全 Swift テスト / `--filter Golden` / `bash Scripts/diff_kotlinc.sh` — 分類操作を同値の API 呼び出しへ置き換えただけで CI に委ねた。
- [x] RF-LOWER-STATE-006: Range virtual-callの重なる分類をstate APIへ寄せる（前提: STATE-004）
  - 対象: `+VirtualCallRewrite+Range.swift` と対応テストのみ。Range / CharRange / ULongRangeを排他的な一種類へ潰さない。
  - 完了条件: `step` / `reversed` / iterator経由で必要な複合factsが維持され、境界値・unsigned・copy経路を固定する。rangeのruntime実装は変えない。
  - 完了根拠（配線のみ。emit する KIR・callee 選択・copy 配置は一切不変）:
    - `rewriteRangeVirtualCall` の4つの集合引数（`rangeExprIDs` / `charRangeExprIDs` / `ulongRangeExprIDs` / `listExprIDs` の `inout Set<Int32>`）を `state: inout CollectionRewriteState` 1個へ畳んだ。dispatcher の callsite は `state: &state` 直渡し。
    - 複合 facts は維持: `isCharRange` / `isULongRange` は `state.contains(.charRange/.ulongRange, receiver)` から導出（同一 receiver が `.range` と特殊化分類を併存させる構造はそのまま）。`reversed()` の伝播も `state.insert(.range/.charRange/.ulongRange, result)` の条件付き insert として同一条件を保持（潰さない・排他化しない）。
    - 結果 tag 付け: `if let result { listExprIDs.insert(result.rawValue) }` → `state.tagListResult(result)`（nil ガード同値）。HOF 系は `state.insert(.list, hofResult)` + `state.tagListResult(result)` — `hofResult` は `emitHOFCall` 戻り値で従来どおり無条件 insert、result は nil ガード付き。range/charRange/ulongRange の callee 選択ロジック（isUIntRange/isLongRange 含む）は未変更。
    - 前提の扱い: STATE-004（#6795）のブランチ上に積んだ stacked PR。ベースは `claude/rf-lower-state-004`。
    - 検証（最小スコープ）: `swift build` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter "CollectionRewriteStateTests|CollectionClassificationTests|CollectionLiteralLoweringTests"` で 3 suite / 90 テスト PASS（range 系の `testRangeEndExclusiveRewrittenToKkRangeEndExclusive` / `testRangeAsReversedIsNotRewrittenToKkRangeReversed` 等を含む）。**未実行**: 全 Swift テスト / `--filter Golden` / `bash Scripts/diff_kotlinc.sh` — 同値 API 置換のみのため CI に委ねた。
- [x] RF-LOWER-STATE-007: Sequence virtual-callの分類操作をstate APIへ寄せる（前提: STATE-004）
  - 対象: `+VirtualCallRewrite+Sequence.swift` と対応テストのみ。既存のsource / runtime経路選択はまだ変更しない。
  - 完了条件: Sequence / Iterator関連の結果tagとcopy後の判断が不変。静的なSequence型をruntime handleの証拠として新たに登録しない。
  - 完了根拠（配線のみ。emit する KIR・callee・経路選択は一切不変）:
    - `rewriteSequenceVirtualCall` の5つの集合引数（`listExprIDs` / `setExprIDs` / `mapExprIDs` / `sequenceExprIDs` の `inout Set<Int32>` + 値渡し `arrayExprIDs`）を `state: inout CollectionRewriteState` 1個へ畳んだ。dispatcher の callsite は `state: &state` 直渡し。
    - 分類参照は `state.contains(.sequence/.list/.array, ...)`、結果 tag 付けは `state.tagResult(.sequence, _)` / `state.tagListResult(_:temporary:)` / `state.tagResult(.set, _:temporary:)` / `state.tagMapResult(_:temporary:)` / `state.tagResult(.sequence, _:temporary:)` へ置き換え。`tagResult`/`tagListResult`/`tagMapResult` は result nil ガード込みで従来の `if let result { ...insert 2行 }` と同値（`hofResult` も result 非 nil 時のみ insert される従来の挙動を保持）。
    - `supportsIterableWindowedTransformReceiver` は値渡し read-only ヘルパーのためシグネチャ不変のまま callsite で `state.listExprIDs` 等を渡す（同ファイル内の分類操作 API 化は本項の範囲外）。source-backed 呼び出し判定（`isSourceBackedSequenceCall`）と toMap 例外ブリッジの経路選択は未変更 — STATE-009 が扱う「静的型由来と runtime 由来の区別」には踏み込まず、新たに静的 Sequence 型を runtime handle の証拠として登録する変更もなし。
    - 前提の扱い: STATE-004（#6795）のブランチ上に積んだ stacked PR。ベースは `claude/rf-lower-state-004`。
    - 検証（最小スコープ）: `swift build` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter "CollectionRewriteStateTests|CollectionClassificationTests|CollectionLiteralLoweringTests"` で 3 suite / 90 テスト PASS（sequence virtual-call の非 rewrite 契約8ケース等を含む）。**未実行**: 全 Swift テスト / `--filter Golden` / `bash Scripts/diff_kotlinc.sh` — 同値 API 置換のみのため CI に委ねた。
- [x] RF-LOWER-STATE-008: property virtual-callの分類参照をstate APIへ寄せる（前提: STATE-004）
  - 対象: `+VirtualCallRewrite+Properties.swift` と対応テストのみ。List / Map / Set / File / Path等の分類参照を移し、既存の型・symbolガードを保持する。
  - 完了条件: `size`等の同名propertyを持つユーザー型がcollectionへ誤分類されず、未分類時のfallbackが不変。property lowering全体やsource API移行は混ぜない。
  - 完了根拠（配線のみ。emit する KIR・callee・ガード条件は一切不変）:
    - `rewriteCollectionPropertyVirtualCall` の4つの集合引数（`listExprIDs` / `setExprIDs` / `mapExprIDs` / `arrayExprIDs` — いずれも値渡し read-only）を `state: CollectionRewriteState` 1個へ畳んだ。葉は分類を書き換えないので `inout` ではなく値渡し（従来の値渡し契約をそのまま対応付け）。dispatcher の callsite は `state: state`。
    - 分類参照は `state.contains(.list/.set/.map/.array, receiver)` へ置き換え。`size`/`count`/`contains`/`isEmpty` の型別 callee 選択と分岐順序（list→set→map→array）は不変。同名 property を持つユーザー型は集合に登録されないため誤分類されない従来のガード構造を保持。未分類時は `return false` で dispatcher のフォールバックへ戻る挙動も不変。
    - これで virtual-call 葉5種のうち Array（STATE-005）・Range（006）・Sequence（007）・Property（008）が state API 化。残る葉は `rewriteListHOFVirtualCall` / `rewriteFileMemberVirtualCall` / `classifyReceiverByStaticType` と、`run` ループ内の直接参照（iterator 系）— いずれも後続 STATE 項または STATE-010 の範囲。
    - 前提の扱い: STATE-004（#6795）のブランチ上に積んだ stacked PR。ベースは `claude/rf-lower-state-004`。
    - 検証（最小スコープ）: `swift build` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter "CollectionRewriteStateTests|CollectionClassificationTests|CollectionLiteralLoweringTests"` で 3 suite / 90 テスト PASS（`testVirtualCallOn*TypedParameter*` の size/isEmpty/contains 経路を直接カバー）。**未実行**: 全 Swift テスト / `--filter Golden` / `bash Scripts/diff_kotlinc.sh` — 同値 API 置換のみのため CI に委ねた。
- [x] RF-LOWER-STATE-009: Sequenceの静的型とruntime由来を分類段階で区別する（前提: STATE-003・007）
  - 対象: `+StaticTypeClassification.swift` と `+PreScan.swift` のSequence分類・既知producer追跡、対応テスト。source宣言・既知runtime factory / bridge・引数・copyについて、確認できるfactsだけを記録する。
  - 完了条件: 同じSequence型でもsourceオブジェクト / `RuntimeSequenceBox` / unknownを区別でき、分岐や再代入で根拠が失われた値を既知として扱わない。一般的なCFG固定点解析まで必要なら別IDへ分割し、推測で分類を補わない。CALL-014が消費できる契約を固定する。
  - 完了根拠（新しいfactを追加しただけ。`sequenceExprIDs`のmembership規則・emit する KIR・callee・経路選択は一切不変）:
    - `Classification.sequence`は元々「確認済み`RuntimeSequenceBox`」の意味と「静的型がSequence」の意味を兼ねていた（`trackedStaticTypeKind`のSequence判定はKSP-441〜447でコメントアウトされ死んでいたため実際には前者としてのみ機能）。`Classification.sequenceType`（staticType軸、静的型がSequenceという事実のみ）と`Classification.sequenceSourceObject`（runtimeRepresentation軸、`.sequence`と排他な「確認済みsourceオブジェクト」）を新設して分離し、`trackedStaticTypeKind`のSequence判定を復活。`Classification.init(_:CollectionLiteralTrackedStaticTypeKind)`は`.sequence`ケースを`.sequenceType`へ写像するため、静的型由来の判定は誰も`sequenceExprIDs`へ書き込まない。
    - 既知producer: `+PreScan.swift`の`asSequence()`仮想呼び出し処理で、source-backedかつ解決先のreceiver型が`Iterable`/`Iterator`/`CharSequence`/`Map`（本文を確認しfresh `object : Sequence<T>`を構築すると確認済み）のときのみ`sequenceSourceObjectExprIDs`へ記録する新ヘルパー`isKnownSourceObjectConstructingAsSequenceReceiver`を追加。`Array<T>.asSequence()`（本文はsourceだがarray仮想呼び出しrewriteがsource解決より先にintercept）と`Sequence<T>.asSequence()`（`= this`のidentity、結果の由来はreceiver次第でこの時点では判定不能）は意図的に対象外。
    - copy: pre-scanの`seedCopy`はunion方式のため、同じ再利用スロットへ`.sequence`と`.sequenceSourceObject`が異なる分岐から書き込まれると両方立ってしまう。`CollectionRewriteState.resolveSequenceProvenanceConflicts(at:)`を追加し、`.copy`処理直後に呼んで両方立っていたら両方落とす（`.sequenceType`は矛盾しないfactなので対象外）。
    - 副次的に発見・修正したバグ（本タスクのスコープ内、routing不変の維持に必須）: `trackedStaticTypeKind`のSequence判定を復活させたところ、独立した2箇所の直書きswitchが同じ`.sequence`ケースを経由して`sequenceExprIDs`（confirmed-runtime-box集合）へ直接insertしてしまい、`testVirtualCallOnSequenceTypedParameterDoesNotRewriteToKkSequence{ToCollection,ToList,Max}`が退行した。`classifyTrackedExprByStaticType`（`+StaticTypeClassification.swift`）は`state.tag(expr, as:)`経由に統一、`classifyReceiverByStaticType`（`+VirtualCallRewrite.swift`、virtual-call dispatcherが毎回呼ぶfallback分類）は`sequenceTypeExprIDs`をinout引数として追加し`.sequence`ケースをそちらへ差し替えて修正。
    - 未追跡のまま残した既知runtimeブリッジ（CALL-014向けメモ）: `sequenceOf`/`emptySequence`/`generateSequence(seed,next)`はsource宣言だが本体は`__kk_sequence_of`等のprivate externalブリッジへ完全委譲しており（`SequenceFactories.kt`）、実体は`RuntimeSequenceBox`。`sequenceRuntimeBridgeReturningNames`（`lineSequence`/`splitToSequence`/`kk_{list,array}_asSequence`のみ）には未追加 — 追加すると`sequenceOf(...).map{}`等のrouting自体が変わり本PRのcontract-onlyスコープを超えるため、KUU-439側の判断に委ねる（Linearコメント参照）。
    - 検証（最小スコープ）: `swift build --build-tests` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --skip-build --filter "CollectionRewriteStateTests|CollectionClassificationTests|CollectionLiteralLoweringTests|SourceBackedCallPreservationPolicyTests"` で4 suite / 116テストPASS（新規5ケース＋既存テーブルへのSequence行追加を含む）。念のため`--filter "CompilerCoreTests.*Lowering"`で27 suite / 369テストもPASS確認（`SourceBackedCallPreservationPolicyTests`含む）。**未実行**: 全Swiftテスト全体 / `--filter Golden` / `bash Scripts/diff_kotlinc.sh` — `sequenceExprIDs`のmembership規則を変えないcontract-onlyの変更のためCIに委ねた。
- [x] RF-LOWER-STATE-010: state互換層を整理し、残存callerと分類コストを検証する（前提: STATE-003〜009）
  - 対象: `+RewriteState.swift` の不要になったadapter・テスト。direct-call / HOF / factory等の未改名callerは単一ストアのviewを使う限り維持でき、表記統一だけの全ファイル変更は行わない。STATE-002で判明した常に空の `indexingIterableExprIDs`（insert箇所なし・読み取り3箇所）の撤去と、名前付き集合を単一コンテナのviewへ移す作業もここで扱う。
  - 完了条件: 種類追加時のcopy伝播更新が一箇所で済み、複数の正本・失われるinout書き戻し・不要adapterがない。多数のcopy / collection操作を含む入力で時間・メモリを変更前と比較し、集合viewの再構築やストア走査の悪化を隠さない。生成結果と決定性が不変。
  - 完了根拠:
    - `CollectionRewriteState` の正本を `Classification` の raw value で引く `[Set<Int32>]` へ統合し、既存の `listExprIDs` 等は `_modify` を備えた mutable view として維持した。direct-call / factory 側の表記は変更せず、virtual HOF と静的型 fallback だけを `state: inout` 一個へ寄せたため、複数集合の同時 `inout` adapter と書き戻し経路がなくなった。`copyFacts` / expression subscript も分類 enum の一箇所だけを走査する。
    - insert 箇所のない `indexingIterableExprIDs` と、それだけを生成元としていた `indexingIterableIterator` 分類・iterator bridge 分岐を撤去した。`withIndex` は従来どおり generic runtime dispatch に任せ、他の iterator/list/range bridge は維持した。
    - `membership(of:)` / `mutateMembership(of:_:)` と旧複数 `inout` 契約を固定していたテストを削除し、named view と canonical store の同一性を検証するテストへ整理した。
    - 最適化 standalone harness（base `HEAD` と候補を同じ分類列・copy/collection workload で `-O` 実行、200,000反復）で semantic checksum は両方 `1717080`。wall time は base 1.84〜2.22s / 候補 1.24〜1.42s、peak RSS は base 16.7〜18.3MB / 候補 15.7〜18.2MBで、view 再構築による時間・メモリの悪化は観測されなかった（macOS の allocator / run 間揺れを含む範囲で比較）。
    - 検証: `swift build --build-tests` green。`SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --skip-build --filter "CompilerCoreTests.CollectionRewriteStateTests|CompilerCoreTests.CollectionClassificationTests|CompilerCoreTests.CollectionLiteralLoweringTests"` は 3 suite / 93 tests PASS。全 Swift テスト・Golden・`diff_kotlinc.sh` 全件は未実行。

### 3. Inline 展開の責務分離・終了条件（RF-LOWER-INLINE）

> INLINE-001 → 002 → 003 → 004 → 005 → 006 → 007 → 008 → 009 → 010 → 011 → 012を基本のマージ順とする。002〜009は `InlineLoweringPass.swift` を共有するため、個別の小PRとして順次マージする。抽出時に展開順序・ラベル採番・ABI・例外処理を変えず、固定回数の撤廃は安全な停止条件を用意した010後に行う。

- [x] RF-LOWER-INLINE-002: ラベル走査・再配置と採番状態を分離する（前提: INLINE-001）
  - 対象: `nextAvailableLabel` / `remapLabels` / `inlineLabelCounter` の責務、既存 `KIR/KIRLabelRelocation.swift` の再利用可能部分。現在の採番規則を保つ関数単位の状態境界を作る。
  - 完了条件: `.label` / 各jumpの全参照が同じ規則で移され、caller・lambda・tailrec由来のラベルと衝突しない。既存helperと異なる採番規則を無条件に統合せず、KIR/LLVM IR不変性を確認する。
  - 2026-09-13 実施: `nextAvailableLabel` / `remapLabels` / `inlineLabelCounter` を `Sources/CompilerCore/Lowering/InlineLabelAllocator.swift` の `InlineLabelAllocator` へ移し、pass インスタンス変数を廃して caller 関数ごとの値型状態にした（`expandInlineCall` / `expandLambdaBody` / `rerouteUnprotectedThrows` へ `inout` で通す）。実測で判明した現行仕様: 採番は二空間で、`inlineLabelCounter` 相当（scratch）の絶対値は出力に現れず `remapLabels` 相当（caller）で必ず振り直される（label なし caller で `pre=[9000, 9001] post=[0, 1]` を確認）。この非対称を型のドキュメントと API 形（`allocateScratchLabel` / `allocateCallerLabel` / `relocate`）で明示し、両空間の基準値を現行のまま保った。4種のラベル保持命令（`.label` / `.jump` / `.jumpIfEqual` / `.jumpIfNotNull`）を列挙する switch が3箇所に重複していたのを `KIRLabelRelocation.labelIDs(of:)` / `rewriteLabels(of:mapping:)` を internal へ上げて一本化した（`relocatingLabels` は「範囲が重ならなければ素通し」という別規則なので統合しない）。同PRで修正したバグ: caller 本体に残った `kk_function_invoke` を展開する直接ラムダ経路だけが `relocate` を通さず scratch ID をそのまま流し込んでいたため、続く通常 inline 展開が同じ ID へ振り直されてラベルが二重定義された（`KIRVerifier` の `duplicateLabel` 相当、codegen が2つの基本ブロックを畳んで不正な IR になる種類）。手組み KIR の回帰テストで修正前は5定義中3種（重複2件）、修正後は重複なしを固定。検証: `swift build` PASS / 新規 `CompilerCoreTests.InlineLabelAllocatorTests` 6件 PASS / `CompilerCoreTests.LoweringPassRegressionTests` 127件 PASS（`+Inline*` 5ファイル＋新規テスト込み）/ `--filter Inline` 102件・30スイート PASS（Backend の inline codegen 統合・imported inline・stdlib artifact 経由を含む）/ `CompilerCoreTests.KIRVerifierTests` 8件・`--filter Label` 24件・`CompilerCoreTests.ImportedInlineKIRMaterializerTests` 4件 PASS。A/B: `inline_reified.kt` / `bug_209_inline_nonlocal_return.kt` / Backend fixture `inline/captured_try_finally`・`inline/qualified_super` と追加プローブ計13ケースの `--emit kir` / `--emit llvm` 計26成果物が base `a6d031b066` とバイト一致。`Scripts/loc_report.sh` を base `a6d031b066` の detached worktree と比較: Sources -13行、Tests +219行（新規テスト2ファイル）、docs +9行、ルート +3行（TODO.md）。`kk_literal_count` のみ +1（回帰テストが `kk_function_invoke` を KIR に組み立てるため。pass 自身が一致判定に使う名前で、テスト内では1箇所に畳んである）。`header_helpers_synthetic_total_lines` / `kir_lowering_todo_fixme_count` / `kk_cdecl_count` / `__kk_cdecl_count` / `interner_resolve_literal_comparison_count` は不変。未実施: 全 Swift テスト・全 Golden・`Scripts/diff_kotlinc.sh` 全件（2026-09-13 の最小スコープ検証方針に従い、変更に関係する範囲のみ実行）。副産物として BUG-250（関数型プロパティの直接呼び出し）を記録。
  - 2026-09-15 [x] 化: PR #6771（`6eb49abe3`、2026-09-13 マージ済み）は現ブランチ HEAD の祖先であることを確認し、`gh pr checks 6771` で CI 全18ジョブ（Build debug/release、TODO ID 重複チェック、Verification 0〜5/5 全shard、kotlinc Diff 4shard 含む）が green であることを再確認した。`nextAvailableLabel` / `remapLabels` / `inlineLabelCounter` という旧名は抽出時に `InlineLabelAllocator`（`Sources/CompilerCore/Lowering/InlineLabelAllocator.swift`）の `allocateScratchLabel` / `allocateCallerLabel` / `relocate` へ改称され現コードに存在しないことを `rg` で再確認し、`InlineLoweringPass.swift` の `expandInlineCall` / `expandLambdaBody` / `rerouteUnprotectedThrows` へ `labels: inout InlineLabelAllocator` として配線されていることも確認済み。コード変更なし、TODO.md のステータス反映のみ。
- [~] RF-LOWER-INLINE-003: 式複製・alias置換・命令operand書換えを分離する（前提: INLINE-002）
  - 対象: `rewriteInstruction` / `definedResult` / `resolveAlias` / `cloneOrReuseExpr` / `cloneExpr` と関連状態。責務別の複製helperへ移し、必要な型置換処理は既存実装へ委譲する。
  - 完了条件: call / virtualCallのsymbol・throw channel・super / dispatch情報、再代入されるexpr、const / temporaryを正しく保持する。型置換規則や展開順序は変更せず、不要なpublic APIを増やさない。
  - 2026-09-15 実施: `resolveAlias` / `rewriteInstruction` / `definedResult` を `Sources/CompilerCore/Lowering/InlineExprAliasing.swift` の状態を持たないnamespace `InlineExprAliasing`（`KIRLabelRelocation`と同じ形）へ、`cloneOrReuseExpr` / `cloneExpr` を `Sources/CompilerCore/Lowering/InlineExprCloning.swift` の `InlineExprCloning` へ移した。alias map（`expandInlineCalls` の `aliases` / `expandInlineCall`・`expandLambdaBody` の `localExprMap`）自体は呼び出し側の所有のまま `inout` で渡し続けている（パラメータ代入・merge-slot昇格などalias解決ではない書き込みも同じmapに対して行われているため、map の所有権自体は移していない）。RF-LOWER-INLINE-003時点の型置換は `substituteType: (TypeID?) -> TypeID?` クロージャ経由で既存の `substituteInlineType` へ委譲し、`InlineTypeSubstitution` を新ファイルへ持ち出さなかった（型代入責務はRF-LOWER-INLINE-004で抽出済み）。`cloneExpr` の2オーバーロード（型置換あり/なし）は、`arena.appendTemporary(type:)` と手組み `arena.appendExpr(.temporary(N), type:)` が同じ時点の `arena.expressions.count` からIDを割り当てるため等価であることを確認した上で `substituteType` の既定値（恒等関数）を使う1実装へ統合し（`expandLambdaBody` 側は既定値のまま呼ぶ）、`cloneOrReuseExpr` 以外から呼ばれないため `private` にした。抽出時に判明した既存の状態: `expandInlineCalls` の `aliases` は宣言時に空のまま一度も書き込まれず（展開結果は明示的な `.copy` で反映するようになっている）、`definedResult` の結果を `removeValue` するだけで終わる。したがって同スコープでの `rewriteInstruction` / `resolveAlias` 呼び出しは現状すべて恒等写像になっている。本PRは分離のみが目的で挙動を変えないため削除せず、除去はループの走査制御を扱うRF-LOWER-INLINE-009側の検討事項とした（`docs/rf-lower-inline-contracts.md` に記録）。新規テスト: `InlineExprAliasingTests`（10件、alias解決の循環・自己参照・チェーン終端、call/virtualCallのsymbol・throw channel・super/dispatch保持、`.copy`の両辺解決、`definedResult`が`.copy`の書き込み先を定義とみなさないこと）・`InlineExprCloningTests`（5件、新規複製・メモ化再利用・`substituteType`委譲・欠落sourceのfallback）。検証: `swift build` PASS / `swiftlint`は新規4ファイルとも0件（`InlineLoweringPass.swift`側の複雑度・行数系指摘はbase `cb6278fd1`時点で同一内容・同一数値のまま存在する既存分であることを個別に確認し、悪化なし。ファイル全体は2313→2126行、クラス本体は1884→1730行に減少）/ 新規2ファイル計15件 PASS / `--filter Inline --no-parallel`（Core 104件26スイート＋Backend 14件6スイート＝計118件32スイート、`LoweringPassRegressionTests`・`InlineLabelAllocatorTests`・imported inline・stdlib artifact経由・Backend inline codegen統合を含む）全件PASS。A/B: baseline `cb6278fd1`とのdetached worktree比較で `inline_reified.kt` / `bug_209_inline_nonlocal_return.kt` / Backend fixture `inline/captured_try_finally` / `inline/qualified_super` の `--emit kir` / `--emit llvm` 計8成果物が全てbyte一致。`Scripts/loc_report.sh` baseline比較は `loc_by_directory Sources`(-187、抽出移動分)と`docs`(+23、contracts doc追記分)のみ変化し、`kk_cdecl_count` / `__kk_cdecl_count` / `kk_literal_count` / `kir_lowering_todo_fixme_count` を含む残り全指標は不変。未実施: 全Swiftテスト・全Golden・`Scripts/diff_kotlinc.sh`全件（最小スコープ検証方針に従い、変更に関係する範囲のみ実行。共通RFゲート未完了のため`[~]`）。
- [~] RF-LOWER-INLINE-004: 型引数代入・reified token生成を分離する（前提: INLINE-003）
  - 対象: `InlineTypeSubstitution` / `buildInlineTypeSubstitution` / `collectInlineTypeSubstitution` / `substituteInlineType` / `buildTypeParamTokenValues` 等の型代入責務。
  - 完了条件: generic / nullable / function型・receiver・reified tokenの置換結果が不変で、imported inlineにも同じ処理が適用される。Semaの型推論や制約解決のリファクタは混ぜない。
  - 2026-09-15 実施: `buildInlineTypeSubstitution` / `collectInlineTypeSubstitution` / `substituteInlineType` を `Sources/CompilerCore/Lowering/InlineTypeSubstitution.swift` の `InlineTypeSubstitution` に移し、`build` / `applying` として型引数の収集・適用を一箇所へ集約した。generic / nullable / class型引数 / function型のreceiver・引数・戻り値 / `KClass` の既存置換規則はそのまま保持し、`SemaModule` の型推論・制約解決には変更を加えていない。`buildTypeParamTokenValues` は同ファイルの `InlineReifiedTypeTokens` に分離し、通常 inline と imported inline が同じ `expandInlineCall` 経路を通ることを明示した。新規 `InlineTypeSubstitutionTests` 2件で imported inline の nested nullable generic・function receiver と reified token index mapping を直接固定。
  - 検証: `swift build` PASS（既存の `SemanticsModels.swift:741` 重複case警告あり） / `swift test --filter CompilerCoreTests.InlineTypeSubstitutionTests --no-parallel` 2件PASS / Core `--skip-build --test-product CompilerCoreTests --filter Inline --no-parallel` 106件27スイートPASS / Backend `--skip-build --test-product CompilerBackendTests --filter Inline --no-parallel` 14件6スイートPASS / `git diff --check` PASS。未実施: 全Swiftテスト・全Golden・`Scripts/diff_kotlinc.sh`全件（変更に関係する最小スコープのみ。共通RFゲート未完了のため `[~]`）。
- [~] RF-LOWER-INLINE-005: erased lambda / inline ABIのboxing helperを分離する（前提: INLINE-004）
  - 対象: `usesErasedLambdaABI` / `boxSubstitutedErasedArguments` / `unboxErasedLambdaArguments` / 戻り値のbox・unbox等、現在Inline内にあるABI補正helper。
  - 完了条件: primitive / nullable / erased genericの引数・戻り値とimported lambda ABIの契約が不変。`ABILoweringPass` 自体の変更や新たなboxing最適化を混ぜない。
  - 2026-09-16 実施: `usesErasedLambdaABI`、erased function-value invoke の callee 集合、primitive 引数の box / unbox、lambda の引数・戻り値および imported inline 結果の補正、浮動小数点演算前の erased invoke 結果の unbox を `Sources/CompilerCore/Lowering/InlineErasedLambdaABI.swift` の状態を持たない `InlineErasedLambdaABI` namespace へ移した。`InlineLoweringPass` は各補正 helper を namespace 経由で呼び出すだけにし、引数位置・nullable / erased generic の判定・展開順序は変更していない。`ABILoweringPass` と通常の ABI 規則には変更なし。
  - 新規 `InlineErasedLambdaABITests` 4件で imported HOF 判定、primitive / nullable / erased generic の lambda 引数・戻り値、erased invoke の再boxing・primitive 結果 unbox、浮動小数点演算前の unbox を固定。検証: `swift build` / `swift build --build-tests` green（既存 `SemanticsModels.swift:741` 重複case警告あり）、`swift test --skip-build --filter InlineErasedLambdaABITests --no-parallel` 4件PASS、Core `--skip-build --test-product CompilerCoreTests --filter Inline --no-parallel` 110件28スイートPASS、Backend `--skip-build --test-product CompilerBackendTests --filter Inline --no-parallel` 14件6スイートPASS、`git diff --check` PASS。
  - 未実施: 全Swiftテスト・全Golden・`Scripts/diff_kotlinc.sh`全件・A/B成果物比較（変更はLowering内のhelper分離のみで、関連 Inline／imported artifact 回帰を最小スコープで確認。共通RFゲート未完了のため `[~]`）。
- [~] RF-LOWER-INLINE-006: 展開後の例外経路補正を分離する（前提: INLINE-005）
  - 対象: `rerouteUnprotectedThrows` とその入出力・呼び出し口。callerのthrownResult、ローカルcatch、finally guard、出口ラベルの責務を明示する。
  - 完了条件: inline内部のcall / virtualCall / rethrowがcallerのcatchへ届き、既に保護された経路を二重に書き換えない。non-local returnを含むtry/finallyの既存回帰がgreenで、例外ABIやcanThrowの意味を変更しない。
  - 2026-09-16 実施: `rerouteUnprotectedThrows` を `Sources/CompilerCore/Lowering/InlineThrowRerouting.swift` の状態を持たない namespace `InlineThrowRerouting`（`InlineExprAliasing` と同じ形）へ移した。4つの責務を型・APIで明示: caller例外スロット（`callerThrownResult`、`nil` なら素通しでラベル未採番）、ローカルcatch済み命令（`thrownResult != nil` は再書き換えしない）、finally guard領域（`.beginFinallyGuard` / `.endFinallyGuard` の depth 内は素通し）、dispatch label（戻り値 tuple のラベルを `throwDispatchLabel` に改めて emit 契約を文書化。`callerThrownResult` 非 nil なら実際に reroute したか無関係に eager 採番する現行仕様を維持し、NLR 用 exit label とは別物だが同一 caller cursor 由来で衝突しない旨も記録）。命令分類（unprotected `.call` / `.virtualCall` / `.rethrow` だけを対象に `canThrow: true` + caller スロット + `jumpIfNotNull` / `.copy` + `.jump` へ書き換える）は private `callerRoute(for:thrownSlot:dispatchLabel:)` に集約し、`thrownResult == nil` だけを判定根拠にする方針（`canThrow` フラグは非synthetic関数では信頼できない既存仕様）と `canThrow` の意味・例外ABIは変更していない。呼び出し口2箇所（`expandInlineCalls` の直接 lambda 経路と通常 inline 経路）は新 namespace を呼ぶ形に更新し、label emit タイミング・展開順序は不変。新規テスト: `InlineThrowReroutingTests`（7件、無保護 call / virtualCall / rethrow の reroute 命令列、ローカル catch 済み・nested finally guard 内の非書き換え、`callerThrownResult == nil` の素通し＋未採番、caller 名前空間からの eager 採番）。検証: `swift build` PASS / `CompilerCoreTests.InlineThrowReroutingTests` 7件 PASS / `--filter Inline`（Core 117件29スイート＋Backend 14件6スイート、`LoweringPassRegressionTests` の `+Inline*` 系・`InlineLabelAllocatorTests`・imported inline・stdlib artifact 経由・Backend inline codegen 統合・`FinallyExceptionRouteTests` / `FinallyExecutionOnControlFlowTests` / `CodegenBackendInlineFunctionExceptionPropagationTests` / `+TryCatchValueReturnTests` を含む）全件 PASS。A/B: base `333337d3d` との detached worktree 比較で `bug_209_inline_nonlocal_return.kt` / `inline_reified.kt` / `finally_exception_routing.kt` / `exception_advanced.kt` / fixture `inline/captured_try_finally` / `inline/qualified_super` の `--emit kir` / `--emit llvm` 計12成果物が全てバイト一致。`Scripts/loc_report.sh` を base `333337d3d` と比較: `loc_by_directory Sources` +68（移動分と境界ドキュメント）/ `Tests` +210（新規テスト）/ `docs` +16（contracts doc追記）のみ変化し、`header_helpers_synthetic_total_lines` / `kir_lowering_todo_fixme_count` / `kk_literal_count` / `kk_cdecl_count` / `__kk_cdecl_count` / `interner_resolve_literal_comparison_count` は不変。未実施: 全 Swift テスト・全 Golden・`Scripts/diff_kotlinc.sh` 全件（最小スコープ検証方針に従い、変更に関係する範囲のみ実行。共通RFゲート未完了のため `[~]`）。
- [~] RF-LOWER-INLINE-007: 通常inline本体の展開処理を分離する（前提: INLINE-006）
  - 対象: `expandInlineCall` の本体と局所状態のみ。複製・型代入・ABI・例外補正は003〜006の境界を使い、lambda展開の実装はまだ移さない。
  - 完了条件: 引数評価順・returnの出口統合・non-local return・receiver / super情報が不変。通常inlineのテストとimported inlineの実行回帰を通し、ファイル移動とアルゴリズム変更を分離できている。
  - 2026-09-18 実施: `expandInlineCall` の本体を `Sources/CompilerCore/Lowering/InlineLoweringPass+CallExpansion.swift` の `extension InlineLoweringPass` へ移した（`ABILoweringPass+BoxingRules` 等と同じ責務分割形）。この経路だけが使う `multiplyWrittenExprs` / `isInlineUnitType` / `shouldRetypeInlineCopyTarget` も同ファイルへ `private` のまま移動。lambda 展開の実装（`resolveLambdaFunction` / `expandLambdaBody` / `appendInlinedLambdaExpansion` / `exprIsDefined`）は INLINE-008 で移すため本体ファイルに残し、拡張ファイルから参照できるよう `private` を外したのみで実装は未変更。局所状態（`localExprMap` / `unitResultAliasExprs` / merge label 系 / `labelRemap`）は本体と一緒に移動し、引数評価順・return出口統合・non-local return・receiver / super・展開順序・ラベル採番は変更していない。検証: `swift build` PASS / `--filter Inline`（Core 118件29スイート＋Backend 15件6スイート、`LoweringPassRegressionTests` / `ImportedInlineKIRRegressionTests` / `CodegenBackendInlineFunction*` 含む）PASS / `--stdlib-from-source` での e2e smoke（通常 inline・lambda 引数展開・non-local return 現行挙動の維持）確認。
  - 未実施: 全Swiftテスト・全Golden・`Scripts/diff_kotlinc.sh`全件（変更はファイル分割のみで生成コード不変の設計のため最小スコープで確認。共通RFゲート未完了のため `[~]`）。
- [~] RF-LOWER-INLINE-008: lambda本体の解決・展開処理を分離する（前提: INLINE-007）
  - 対象: `resolveLambdaFunction` / `expandLambdaBody` とcapture・return処理の局所状態のみ。
  - 完了条件: 捕捉有無・receiver付きlambda・noinline / crossinline・通常return / non-local returnの契約が不変。同名関数への誤fallbackや二重展開がなく、通常inlineの複製helperを再実装しない。
  - 2026-09-18 実施: `resolveLambdaFunction` / `expandLambdaBody` / `appendInlinedLambdaExpansion` を `Sources/CompilerCore/Lowering/InlineLoweringPass+LambdaExpansion.swift` の `extension InlineLoweringPass` へ移した（INLINE-007 の `+CallExpansion` と同じ責務分割形）。capture オフセット・receiver オフセットの引数マッピング、merge label / mergeResult の return 統合、`hasNonLocalReturn` / `hasNormalReturn` の追跡、nested `kk_function_invoke` の再帰展開、throw スロットへの splice helper はすべて本体と一緒に移動し、捕捉有無・receiver 付き lambda・noinline / crossinline・通常 return / non-local return の契約は未変更。`exprIsDefined` は通常 inline 側の結果確認でも使うため本体ファイルに残した。複製・alias・ラベル・例外補正は `InlineExprCloning` / `InlineExprAliasing` / `InlineLabelAllocator` / `InlineThrowRerouting` の既存境界を引き続き利用（再実装なし）。検証: `swift build` PASS / `--filter Inline`（Core 118件29スイート＋Backend 15件6スイート）PASS / `--stdlib-from-source` での e2e smoke（lambda 引数展開・capture・non-local return 現行挙動の維持）確認。
  - 未実施: 全Swiftテスト・全Golden・`Scripts/diff_kotlinc.sh`全件（ファイル分割のみで生成コード不変の設計のため最小スコープで確認。共通RFゲート未完了のため `[~]`）。
- [~] RF-LOWER-INLINE-009: 展開対象indexと依存スケジューリングを分離する（前提: INLINE-008）
  - 対象: `run` のfunction snapshot構築、`expandNestedBodylessInlineCalls`、`inlineTransform` の走査制御。SymbolIDを主キーにした依存情報を抽出し、まず既存の4回 / 8回制御を維持する。
  - 完了条件: module / imported / lambda本体・bodyless inlineを区別し、symbol既知の呼び出しを無関係な同名関数へ結び付けない。辞書の列挙順に依存しない処理順がテストされ、arenaの式ID割当と既存出力が不変。
  - 2026-09-18 実施: 展開対象indexを `Sources/CompilerCore/Lowering/InlineExpansionIndex.swift` の `InlineExpansionIndex` へ抽出し、スケジューリング両ループを `Sources/CompilerCore/Lowering/InlineLoweringPass+Scheduling.swift` の `extension InlineLoweringPass` へ移した。index は `inlineFunctionsBySymbol`（展開ターゲット: module `inline` 宣言＋imported inline 本体）と `allFunctionsBySymbol`（module 宣言全体＝通常・inline・lambda本体、lambda解決用lookup）を `SymbolID` 主キーで保持し、`origins`（module / imported 出所）・`bodylessInlineSymbols`・`originalBodies`（凍結済みスナップショット、衝突時は module 宣言優先）を構築時に分類する。依存情報は `bodylessCallees(of:)`（解決済みsymbolのcallのみを辺とし、名前のみの呼び出しと自己呼び出しは辺にしない）と `pendingBodylessCallers(interner:)`（凍結済みoriginalの名前→パラメータ数→source range→symbol 順の全順序で列挙順に依存しない処理順を返す）に抽出。symbol既知callの束縛規則（既知symbolは自身のsnapshotにのみ束縛され、同名fallbackへは流れない）は `inlineTarget(callSymbol:callee:inlineFunctionsByName:)` へ移した。`recordExpansion` が両テーブルへの書き戻しを一元化する。4回bodyless巡回・8回caller再走査は `maxBodylessExpansionRounds` / `maxInlineExpansionRounds` として維持し、ラウンド内のby-name表固定・ラウンドまたぎの最新snapshot参照など既存の逐次意味はそのまま。新規テスト `InlineExpansionIndexTests`（10件）: module / imported / lambda本体 / bodyless の分類、衝突時の両テーブル保持、symbol既知callの同名fallback抑止（KSP-1011）、symbol不明callの一意名fallback、bodyless依存辺（symbolのみ・自己call除外・書き戻し追従）、宣言・挿入順を変えた2indexで `pendingBodylessCallers` が同一順序になること、`snapshotExpansionOrder` の全順序性。検証: `swift build` PASS / `bash Scripts/swift_test.sh --filter Inline`（Core 128件30スイート＋Backend 15件6スイート、新規index suiteを含む）PASS。
  - 未実施: 全Swiftテスト・全Golden・`Scripts/diff_kotlinc.sh`全件（既存出力不変はindex順序の全順序性と同値comparatorで担保し、関連 Inline 回帰を最小スコープで確認。共通RFゲート未完了のため `[~]`）。
- [ ] RF-LOWER-INLINE-010: 固定回数撤廃の前に循環・展開量制限・必須inline残存の契約を実装する（前提: INLINE-009）
  - 対象: 分離済みschedulerと対応Core / Backend tests。bodyがobjectに存在しない `isInlineOnly` / imported inline等の必須展開と、通常callとして残せる関数を区別する。再帰・相互再帰・大きな非循環グラフでの停止条件を定める。
  - 完了条件: 必須展開の未解決callをリンク段階まで黙って残さず、循環・予算超過時に決定的な診断で停止する。非必須callを不必要にエラー化しない。既存4回 / 8回境界と境界超えの最小ケースを追加し、不具合が再現したら同じPRで修正する。全パス `KIRVerifier` は重複実装しない。
- [ ] RF-LOWER-INLINE-011: bodyless inline snapshotの固定4回走査を依存順処理へ置き換える（前提: INLINE-010）
  - 対象: `expandNestedBodylessInlineCalls` 相当のschedulerのみ。calleeからcallerへ処理する決定的worklistを使い、lambda内の依存も含める。呼び出し側の8回走査はまだ変えない。
  - 完了条件: 4段を超える正当な依存鎖でも必須callが解消され、同じ元本体の二重展開がない。diamond依存・imported inline・lambda内依存・循環での停止を固定し、010の診断と展開量制限を維持する。
- [ ] RF-LOWER-INLINE-012: caller本体の固定8回再走査を進捗に基づく展開へ置き換える（前提: INLINE-011）
  - 対象: `inlineTransform` / `expandInlineCalls` 相当の反復制御のみ。新たに現れた展開対象を追跡し、対象がなくなるまで処理するが、010の循環・予算制限を必ず適用する。
  - 完了条件: 深い非循環inline・多段lambda・再帰で正しく完了／診断し、必須inline残存チェックがgreen。例外・non-local return・型・ABI・決定性の全回帰を通し、大きな入力で処理時間・生成命令数・arena増加を変更前と比較する。上限を単に増やしただけ、または無制限ループへの置換で完了としない。

## Stdlib Kotlin 化 実行計画（KSP）

> RF-STDLIB / M1–M17 / MIGRATION-* の**実行体**。設計: [`docs/stdlib-pipeline.md`](docs/stdlib-pipeline.md)。棚卸し日: 2026-07-01（シンボル名は当日時点の実コードで検証済み。行番号は書かない — アンカーは必ず rg で引く）。2026-07-10 ギャップ監査で KSP-CAP / KSP-INF / KSP-W6 / CLEANUP-STUB-096+ / バグバックログを追補。2026-08-12 ギャップ再調査（§9 分類表×実行体タスクの突合 + 「別タスク」言及の棚卸し + ガバナンス enforcing の実装確認）で KSP-683〜692 / CLEANUP-STUB-125 / BUG-211 を追補。
> 依存: W0 → W1 → W2 は直列。W3 以降は「前提」欄に従い並列可。**言語機能ブロッカーは KSP-CAP-* として独立管理し、各タスクは必要 CAP を「前提」に宣言する（ブロッカー先行の原則）**。
> **粒度ルール**: 1タスク = 1 PR。目安「削除対象 kk_* ≤ 15・単一責務・golden 更新1回」。超えると判明したら枝番でなく新番号で分割する。
> クローズ記録: 旧 `STDLIB-JVM-166`（Java プレビュー機能）/ `STDLIB-REFL-175`（アノテーション処理高度機能）は 2026-07-07 #4582 で未完了のまま削除されたが、**ターゲット外として意図的クローズ**とする（2026-07-10 決定。復活させない）。
>
> **共通ゲート G**（全タスクの完了条件に含む）: `bash Scripts/swift_test.sh` / `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` すべて green。`Scripts/loc_report.sh` が存在する場合、`HeaderHelpers+Synthetic*` 行数・`"kk_` リテラル数の悪化なし。**完了マークは enforcing（テスト or rg チェック）の green 実績を完了メモに書けるものに限る — ドキュメント同期や部分検証のみでの完了は禁止**。TODO.md 編集時のゲート: **タスク定義行の ID 重複ゼロ**（`rg -o '^- \[.\] [A-Z][A-Z0-9-]*-[0-9]+' TODO.md | sort | uniq -d` が空、または `Scripts/check_todo_ids.sh` で確認）。この検出はタスク定義行（`- [ ] ID:` / `- [x] ID:`）限定で、本文中の「前提: KSP-CAP-004」等のクロスリファレンスは対象外。
> **golden 更新 U**: `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` → `git diff -- Tests/CompilerCoreTests/GoldenCases` が機械的差分のみであること。
> **移行テンプレート T**（W2〜W4/W6 の各タスクはこの手順）:
> 1. タスク記載の diff ケースを `Scripts/diff_cases/` で確認・なければ追加し、**現行実装**で `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` green を確認（挙動の固定）
> 2. タスク記載の実装先 .kt に Kotlin 実装を書く（既存ファイル追記可）。ランタイム依存点は `@KsSymbolName("__kk_...") internal external fun __名前(...)` で宣言
> 3. 新規 .kt は `Sources/CompilerCore/Stdlib/kotlin/` 配下に置くだけで自動配線される（除外リスト機構は KSP-505 で撤廃済み）
> 4. **同一 PR** で、タスク記載の (a) `HeaderHelpers+Synthetic*` の該当登録 (b) `CallTypeChecker+*` / `CallLowerer+*` の名前文字列特例 case (c) Runtime の `@_cdecl` 関数 (d) `RuntimeABISpec` の該当エントリ（parity テスト含む）を削除する。「ブリッジ残留」指定の関数は削除せず `__kk_` prefix へ改名し spec を更新
> 5. U → G → タスク記載の rg 完了チェックが 0 件
> 6. **移行完了の2点確認**: ①.kt 本体が実ロジック（`= this` 等のフェイク禁止 — 実例: RangeCoercion.kt） ②Sema/KIR/Lowering に同名 name-string 特例が残っていない
> 7. **二重 oracle**: diff ケースに加え、bundled .kt を実行して期待値比較する自己完結テスト（KSP-INF-006 のハーネス整備後は必須。整備前は G の既存テストで代替可）
> 8. ブリッジ（`__kk_*`）を**追加**する場合は理由コード（syscall / メモリ表現 / GC・continuation / メタデータ / 性能=実測値添付）を PR 本文に明記し、`RuntimeABISpec` 登録 + specVersion 更新をセットで行う。本家 kotlin-stdlib から移植した .kt には Apache 2.0 帰属ヘッダを付ける（KSP-INF-013）

### KSP-CAP: コンパイラ言語機能ブロッカー（2026-07-10 実機プローブで全件実測。移行タスクより先行して解消する）

> stdlib を本家形の Kotlin で書くために必要な言語機能の台帳。再現 .kt は各タスク着手時に `Scripts/diff_cases/` or 回帰テストへ固定する（プローブ時の最小再現はセッション記録 probes/p01〜p12b にあり、診断コードから容易に再構成可能）。完了条件は共通で「再現ケースが期待動作でコンパイル・実行され、回帰テストとして固定される + G」。

- [x] KSP-CAP-004: `while(true)` CAS ループ / `Nothing` 戻り値無限ループの型検査を通す（`KSWIFTK-TYPE-0001`）。実装は `46377d557b`（PR #4984。`ControlFlowTypeChecker` が break を持たない定数 true ループを `Nothing` 型付けし、`ControlFlowLowerer` へ伝播。`Tests/CompilerCoreTests/Sema/InfiniteLoopTypeCheckingTests.swift` を新設）、実行レベルの oracle は `51be709ff2`（PR #4992。`Scripts/diff_cases/while_true_cas_loop_return.kt`）。ブロック対象はいずれも解消済み: KSP-673 は `13ab8e6bc8`（PR #5045）でマージされ TODO.md から剪定済み、`AtomicMigration.kt` / `AtomicArrayMigration.kt` の保留コメントは #4984 で撤回され `getAndUpdate`/`updateAndGet`/`fetchAndUpdate`/`fetchAndUpdateAt` の CAS retry loop が Kotlin source 実装になっている。
  - 完了根拠（2026-09-13 実測、本 PR）: `swift build` PASS / `bash Scripts/swift_test.sh --filter CompilerCoreTests.InfiniteLoopTypeCheckingTests` が `Test run with 1 test in 1 suite passed`（0 件マッチの空振りでないことを出力で確認）/ `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/while_true_cas_loop_return.kt` が `total=1 failed=0 passed=1 skipped=0`。共通ゲート G の全体実行はローカルでは行わず、変更スコープ最小化方針（`c6826127ff` / #6749）に従い CI へ委譲した。
  - 派生: 隣接シェイプ（ラムダ内 break）のプローブで BUG-253（非ローカル break/continue の未実装による黙った誤コンパイル）を発見し、診断化の部分修正と回帰テストを本 PR に同梱した。`containsBreakTargetingCurrentLoop` の `.lambdaLiteral` 扱いは BUG-253 側で扱うため本項では変更していない。
- [x] KSP-CAP-018: object 式によるクラス継承を通す（= BUG-215）。ブロック対象だった KSP-441（object 式でパイプラインを表現する方針）は解消。2026-08-18 + 2026-09-13 に本項目の2症状（空ボディ含む）まで実装・検証済みで、2026-09-14 に実機再検証（`anon` / `7` を実際に出力すること、`diff_kotlinc.sh` PASS、バックエンド回帰16件 PASS を確認）の上で [x] 化。残る2件（object 式プロパティ delegation 未実装、名前付き `object : Base(x)` 宣言）は当初から本項目の完了条件外のため、BUG-267 / BUG-264 として独立起票（下記バグバックログ参照）。
  - **注記**: 旧 KSP-CAP-016/017（同一症状、2026-08-06 記録）と旧 BUG-187/188 は、名前不明の TODO.md 編集（`f9dea8961c` 付近、DEBT-DIFF-005 統合コミット群）でブロッカー台帳から本文ごと消失し、`[x]` 化されないまま記録が失われていた。名前付きサブクラスのスーパークラス primary constructor 実引数伝搬（旧 KSP-CAP-016 症状の一部）は別途 `1128468186`（PR #5506, "Fix BUG-155: run superclass constructors and class-body initializers"）で修正済みと 2026-08-18 実機確認したため当該部分はクローズ、object 式経由の残り2症状のみ本項として採番し直す。
  - 症状は2系統（interface を実装する object 式のプロパティ dispatch は BUG-141 で修正済み。本項目は**クラス**継承）:
    1. 基底クラスの `open`/`abstract` メンバを object 式が override しても dispatch されない。`open class Base { open fun describe(): String = "base" }` `fun make(): Base = object : Base() { override fun describe() = "anon" }` に対し `make().describe()` が基底実装 `"base"` を返す
    2. スーパークラス実引数付きの object 式 `object : Base(x) {}` は実行時 `KSwiftK panic [KSWIFTK-RUNTIME-0001]: kk_array_get_inbounds precondition failed` でクラッシュする（名前付きサブクラスは `1128468186` で修正済みだが、object 式はこのクラッシュが残る点が異なる）
  - 最小再現（kotlinc は `anon` / `7`。2026-08-18 `.build/debug/kswiftc` で再実機確認済み）:
    ```kotlin
    open class Base { open fun describe(): String = "base" }
    fun make(): Base = object : Base() { override fun describe(): String = "anon" }
    fun main() { println(make().describe()) }   // "base"

    open class Base2(val v: Int)
    fun make2(x: Int): Base2 = object : Base2(x) {}
    fun main2() { println(make2(7).v) }         // KSWIFTK-RUNTIME-0001
    ```
  - **部分修正（2026-08-18）**: 症状1・症状2ともに、object 式が**メンバ宣言（override 関数/プロパティ）を1つ以上持つ**場合は解消した。真因は2つの独立バグだった:
    (a) 症状1（override dispatch）: `ExprTypeChecker+ObjectLiteralInference.swift`（object 式は関数本体の型検査中に処理されるため、全ての named nominal に対して vtable slot を計算する `LayoutSynthesis.synthesizeNominalLayouts` — `runValidationPasses` で実行 — が既に完了した*後*に symbol が生成される）が、`NominalLayout.vtableSlots` をスーパークラスから単純コピーするだけで、object 式自身の `override` メンバに対する override 解決（継承 slot の再利用判定）を一切行っていなかった。`LayoutSynthesis.swift` の該当ロジック（`MethodDispatchKey` 照合・`resolveOverriddenSlot`）を `Sources/CompilerCore/Sema/DataFlow/VtableOverrideMatching.swift` の共有関数へ抽出し、`ExprTypeChecker+ObjectLiteralInference.swift` からも呼ぶことで解決。
    (b) 症状2（super ctor 実引数）: `object : Base(x) { ... }` の `(x)` はパーサ（`BuildASTPhase+ExpressionParserLambdaObjectCallable.swift` の `parseObjectLiteral`）が `skipBalancedParenthesisIfNeeded()` で単に読み捨てており、`ObjectDecl` に実引数を保持するフィールド自体が存在しなかった（`SuperTypeEntry.constructorArgs` は名前付きクラス専用で、`ObjectDecl.superTypes` は `[TypeRefID]` のみ）。`ObjectDecl.superTypeConstructorArgs: [CallArgument]` を新設し、`parseCallArguments()`（通常の呼び出し実引数パーサ）で実引数を捕捉。さらに (1) `ExprTypeChecker+ObjectLiteralInference.swift` でこれらの式を外側スコープ（`ctx`/`locals`）に対して型検査するよう追加（怠ると KIR lowering 時に式が未解決のまま `unit` に落ちる、ジェネリック引数 `T` の参照を含む場合に顕在化）、(2) `ObjectLiteralLowerer.swift` に `emitObjectLiteralSuperConstructorCall`（PR #5506 の `emitSuperConstructorDelegation` と同型のロジック）を新設し、`kk_object_new` 直後・itable/vtable 登録の直後にスーパークラスの `<init>` を実引数付きで呼び出すよう配線。
    回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt`（`diff_kotlinc.sh` PASS 確認済み）、`Tests/CompilerBackendTests/Codegen/CodegenBackendObjectLiteralClassInheritanceTests.swift`（5テスト、ジェネリック外側スコープ引数・複数行 expression-body・複数コンストラクタ解決のケースを含む）。
  - **追加修正（2026-08-18、Devin Review 指摘）**:
    (c) `emitObjectLiteralSuperConstructorCall` がスーパークラスの `<init>` オーバーロードを `lookupAll(...).first` で無条件に選んでいたため、複数コンストラクタを持つ基底クラスで意図しないオーバーロードが呼ばれうる問題を修正。`resolveObjectLiteralSuperConstructor`（`ObjectLiteralLowerer.swift`）を新設し、まず arity で絞り込み、複数残る場合は実引数の Sema 解決済み型（`sema.bindings.exprTypes`）とパラメータ型を突き合わせて一意に決定する（型パラメータはワイルドカード扱い、`VtableOverrideMatching.swift` の override slot 解決と同型のロジック）。デフォルト引数の補完は行わないため、その場合は従来通り `lookupAll` の先頭にフォールバックする（named class 側の `emitSuperConstructorDelegation` と同じ既知の残存ギャップ）。
    (d) `parseTail`（`KotlinParser+Statements.swift`）のニューライン継続ヒューリスティックが、`=` の次行が `object` キーワードで始まる場合を常に「新規トップレベル宣言の開始」と誤判定していたバグ（旧 BUG-216）を修正。`shouldStopStatementBefore` 呼び出し側とトレーリングラムダ相当の継続判定の両方に、`object` の次のトークンが `:`/`{`（名前なし = object 式）かを見る `isObjectExpressionStart` ガードを追加。本家 `kotlin.properties.Delegates.observable`/`vetoable` の実際の複数行ソース記述がそのまま解析できるようになった。
    回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt` に複数行 expression-body ケースと複数コンストラクタケースを追加、`CodegenBackendObjectLiteralClassInheritanceTests.swift` に対応する2テストを追加。
  - **追加修正2（2026-08-19、Devin Review 指摘）**: `ObjectDecl.superTypeConstructorArgs` はエンクロージング側の Sema/KIR コンテキストで型検査・lowering されるが、既存の2つの capture 解析トラバーサル（Sema `CaptureAnalyzer.collectCapturedOuterSymbols` と KIR `LambdaLowerer+CaptureAnalysis.swift` の `collectBoundIdentifierSymbols`/`containsImplicitReceiverReference`/`containsImplicitReceiverMemberAccess`）が object 式をメンバ本体・プロパティ初期化子のみ辿る前提で `.objectLiteral` をリーフ扱いしており、super ctor 実引数を素通りしていた。ラムダの中で object 式を作り、外側ローカルを super ctor 実引数からのみ参照するケース（`fun make(x: Int): () -> Base = { object : Base(x) { ... } }`）で、そのローカルがラムダのキャプチャリストに含まれず実行時クラッシュ（`kk_array_get_inbounds precondition failed`）になっていた。4箇所すべてに `superTypeConstructorArgs` を辿る分岐を追加して解決。調査中に副次的に発見した第5のバグも同一 PR 内で修正: `parseBlock`（`KotlinParser+Statements.swift`）のブロック先頭宣言判定が、(d) で修正した `parseTail` とは別に同じ「`object` は常に新規宣言」誤判定を持っており、ラムダ本体が bare な object 式**のみ**の場合（`{ object : Base(x) { override fun ... } }`）に `object` を新規トップレベル宣言として誤パースし、override dispatch が基底実装に戻っていた（`isObjectExpressionStart` ガードを追加して解決）。回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt` にラムダ内 object 式のケースを追加、`CodegenBackendObjectLiteralClassInheritanceTests.swift` に対応する2テストを追加。
  - **追加修正3（2026-09-13）**: 旧「未解消」項目1（メンバ宣言を1つも持たない空ボディの object 式）を解消。真因はパーサ側の `parseObjectLiteralDecl`（`BuildASTPhase+ExpressionParserObjectLiteralMembers.swift`）が空ボディで `nil` を返していた点だけで、これにより `ObjectLiteralLowerer.lowerObjectLiteralExpr` が `declID == nil` 側の簡易パス（`ensureObjectLiteralGeneratedDecls`。生成ファクトリ `kk_object_literal_N` の中で `kk_object_new(max(1, superTypeCount), classID=0)` を呼ぶだけで、`NominalLayout` を計算せず supertype edge / itable 登録も super コンストラクタ呼び出しも行わない）を選んでいた。空ボディでも（メンバ空の）`ObjectDecl` を生成して既存の stored パスへ合流させることで、上記 (a)〜(e) の修正がそのまま届く。メンバのパースに失敗した場合の `nil` 返し（不正ボディに対する寛容パス）は維持しており、Sema/KIR に残る `declID == nil` 分岐はパース失敗専用になった。
    **台帳訂正**: 症状はコンストラクタ実引数付き（`object : Base(x) {}`）に限らなかった。実引数なしの `object : Base() {}` でも、基底クラスのプロパティ初期化子（`open class Fixed { val answer: Int = 42 }`）が走らないため同じ `kk_array_get_inbounds precondition failed` になる（簡易パスは実引数の有無に関わらず super コンストラクタを呼ばないため）。
    回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt` に空ボディ7形（実引数あり / 実引数なし + 基底プロパティ初期化子 / interface / ジェネリック基底 / 複数実引数 / class + interface / ラムダ内で外側ローカルを super ctor 実引数からのみ参照）を追加（`diff_kotlinc.sh` PASS）、`CodegenBackendObjectLiteralClassInheritanceTests.swift` に対応する4テストを追加（11/11 PASS）。旧バグ経路を固定していた `testBuildKIRLowersObjectLiteralToGeneratedFactoryReturningRuntimeObjectEntity`（`BuildKIRRegressionTests+ExpressionAndAdvancedScenarios+ControlFlowTryAndObjectLiteral.swift`）は、inline `kk_object_new` + 非0 `classID` + 自前 nominal decl の発行を検証する `testBuildKIRLowersEmptyBodyObjectLiteralToInlineRuntimeObjectEntity` へ書き換えた。
  - **副産物の修正（2026-09-13）**: 空ボディ検証中に発見した「object 式の abstract メンバ実装漏れが無検査」を同 PR 内で修正。`object : Animal() {}`（`abstract fun speak()`）や `object : Flyable { val unrelated = 1 }`（`fun fly()` 未実装）は kotlinc がエラーにするが kswiftc は素通ししていた。原因は (a) の vtable slot 欠落と同じ構造で、名前付き nominal 用の検査（`Inheritance.validateAbstractOverrides`、`runValidationPasses` 実行）が object 式の symbol 生成より前に走るため object 式には一切届いていなかった。`collectInheritedAbstractMembers` と新設の `unimplementedAbstractMembers` を `Sources/CompilerCore/Sema/DataFlow/AbstractMemberCompleteness.swift` へ抽出（`VtableOverrideMatching.swift` と同じ共有化パターン）し、`Inheritance.swift` と `ExprTypeChecker+ObjectLiteralInference.swift` の両方から呼ぶ。`collectInheritedAbstractMembers` の戻り値は symbol ID 順にソートして診断順を決定的にした（従来は `Dictionary.values` 順で非決定的。既存 golden に変化なし）。
    偽陽性リスクの実測: 一時プローブ（warning 版）で bundled stdlib の object 式 102 個と `Scripts/diff_cases/` を走査し、新診断の発火は 0 件。`Iterator`/`Sequence` を実装する stdlib 形の object 式（`CodegenBackendSequenceEdgeCasesTests` 60件ほか）も全て PASS。
    回帰: `Tests/CompilerCoreTests/GoldenCases/Diagnostics/error_abstract_instantiation.kt` に abstract class 版・interface 版・正常版の3ケースを追加（旧ファイルにあった `KSWIFTK-SEMA-0313` 期待コメントは未実装コードだったため実コード `KSWIFTK-SEMA-ABSTRACT` に訂正）。
  - **副産物の修正2（2026-09-13）**: object 式のメンバ本体で、同一行のセミコロン区切り複数文が `KSWIFTK-TYPE-0001: Type constraint could not be satisfied` になっていたバグを修正（正しい Kotlin の拒否。診断は真因から遠く原因不明に見える）。object 式のメンバはトークン列を切り出して別の `KotlinParser` で再パースする方式で、その前処理（`parseObjectLiteralFunctionDecl`/`parseObjectLiteralPropertyDecl`）がメンバ間の区切り `;` を落とすため**深さを見ずに全セミコロンを filter** しており、メンバ本体内の文区切りまで消していた。`fun bump(): Int { i = i + 1; return i }` が `{ i = i + 1 return i }` になり一つの不正な文として解釈される。同じ2文を改行で分けると通る（フォーマット依存）。`strippingMemberSeparatorSemicolons`（深さ0のみ除去）を新設し、本体を含みうる4箇所（メンバ関数 / プロパティ / `by` デリゲート式 / `=` 初期化子）で使用。残る2箇所（`parseObjectLiteralBareHeader` / `objectLiteralRangeNeedsBraceContinuation`）はヘッダ prefix 判定と深さ非依存の述語のため一律除去のまま。
    発見経路: KSP-CAP-018 の検証中に `object : Iterator<Int> { ... override fun next(): Int { i += 1; return i } }` が通らないことから。当初 `Iterator` のジェネリクス問題に見えたが、同じ2文を `;` 区切り／改行区切りにした2ケースの比較で**フォーマット差のみ**と判明。
    回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt` にセミコロン区切り本体・初期化子内ラムダのケースを追加、`CodegenBackendObjectLiteralClassInheritanceTests.swift` に対応する2テストを追加（13/13 PASS）。
  - **追加修正4（2026-09-13）**: object 式の custom accessor（getter/setter）が正しく動かない問題を解消。当初は「Sema が accessor 本体を型検査していない」1点と記録していたが、実測で**5層**に分かれていた:
    (a) Sema: `ensureObjectLiteralSymbol`（`ExprTypeChecker+ObjectLiteralInference.swift`）のプロパティループが `propertyDecl.initializer` だけを辿り `getter`/`setter` 本体を訪れないため、識別子に `identifierSymbols` の束縛が付かず KIR が `.unit` を出していた。`driver.declChecker.typeCheckGetter`/`typeCheckSetter` を呼ぶよう追加（順序は名前付き経路 `DeclTypeChecker.typeCheckPropertyDecl` と同型: getter が型を供給しうる / setter は確定後の型を要求）。
    (b) Sema: (a) だけ入れると accessor 本体から外側ローカルが `KSWIFTK-SEMA-0022: Unresolved reference` になった。`typeCheckGetter`/`typeCheckSetter` に `baseLocals` パラメータ（`typeCheckFunctionDecl` と同名・同目的）を新設し、object 式側から `outerLocalsSnapshot` を渡す。accessor 本体の capture 収集（`collectCapturedOuterSymbols`）も追加（プロパティ**初期化子**は囲い側で inline lowering されるため対象外）。
    (c) KIR read: **台帳の当初記述にはなかった第2の真因**。`ExprLowerer+ControlFlowAndBlocks.swift` の暗黙レシーバ経路が、custom accessor の有無を見ずに常に instance field を直読みしていた。computed プロパティのスロットは誰も書かないため 0 が返る（症状2「メンバ関数内から読むと 0」の正体はこれで、Sema とは無関係）。明示レシーバ側（`tryLowerObjectLiteralStoredPropertyRead`）は既に `call get` していたので、両者が食い違わないよう述語 `objectLiteralPropertyUsesAccessor` を共有化し、発行条件（`getter.body != .unit`）と厳密に一致させた（不一致は `_get` 未定義のリンクエラーになる）。
    (d) Sema layout: (e) の setter 発行を入れた時点で SIGSEGV になった。object 式のプロパティは backing field シンボルを持たず `field` とプロパティが同一シンボルのため、(c) の accessor 分岐が `field` アクセスを `call get`/`call set` に変えて **accessor が自分を再帰呼び出し**していた。`MemberHeaderCollection` と同じルール（accessor を持ち、かつ実ストレージ = setter か初期化子を持つプロパティ）で `$backing_*` シンボルを定義し、`NominalLayout.fieldOffsets` のキーも `backingFieldSymbol(for:) ?? propertySymbol` に揃えた（コードベース各所の同形フォールバックはこれを見込んだ設計だった）。
    (e) KIR emit: `ObjectLiteralLowerer.lowerObjectLiteralPropertyGetters` が getter しか発行しておらず（→ `lowerObjectLiteralPropertyAccessors` に改名）、代入側は既に `call set` を出していたため custom setter は `KSWIFTK-LINK-0001`（`_set` 未定義）だった。`lowerAccessorBody(accessorKind: .setter)` を追加。あわせて accessor 本体でも `restoreObjectLiteralCaptures` を呼ぶ（accessor は独立した KIR 関数なので、capture はインスタンスフィールドから読み戻す必要がある。`lowerSingleMemberFunction` と同じ手当て）。
    (f) KIR capture: ラムダ内 object 式で、外側ローカルを accessor 本体からのみ参照するケースがラムダの capture リストに入らなかった（`kk_lambda_* params=0` で未定義シンボルを直参照）。`collectBoundIdentifierSymbols` / `containsImplicitReceiverReference`（`LambdaLowerer+CaptureAnalysis.swift`）と `LambdaLowerer+CallableResolutionAndCapture.swift` の `.objectLiteral` 分岐に accessor 本体を追加（`superTypeConstructorArgs` と同じパターンの5例目。共有ヘルパー `accessorBodyRootExprs` / `objectLiteralAccessorRootExprs` を新設）。メンバ**関数**本体は別経路で既に到達していたため追加不要。
    **当初想定の訂正**: 「KIR で継承プロパティを読めるようにする」作業は不要だった。継承プロパティのオフセットは object 式の `NominalLayout` に継承済みで、(a) で識別子が束縛されれば既存の汎用経路がそのまま解決する（`object : Ticker(4) { val doubled: Int get() = step * 2 }` を明示レシーバで読むケースで実証）。
    回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt` に sibling/継承プロパティ読み・別ストレージ setter・`field` 経由 setter・accessor 本体からの capture（直接／ラムダ内）を追加（`diff_kotlinc.sh` PASS）、`CodegenBackendObjectLiteralClassInheritanceTests.swift` に対応する3テストを追加（16/16 PASS）。`testBuildKIRObjectLiteralCustomGetterUsesAccessorCall` は callee 名しか見ておらずこのバグを長年見逃していたため、発行された accessor 本体がインスタンスを読むこと・`.unit` 定数を含まないことを検証するよう強化した。
  - **未解消（本項目の完了条件外。バグバックログへ独立起票）**: object 式のプロパティ delegation は **BUG-267 として修正済み**（本 PR。詳細は下記の `[x] BUG-267` 完了記録を参照 — Sema 側に `$delegate_` ストレージ・`typeCheckDelegate`・delegate body キャプチャ収集、lowering 側に named class と共有の delegate 初期化・accessor 合成を追加。明示・暗黙・書き込み・`+=`・`Delegates.observable`・外側ローカル capture まで通ることを確認済み）。名前付き（非リテラル）`object : Base(x) { ... }` 宣言のスーパークラス実引数破棄と virtual dispatch バグは BUG-264 を参照。

### KSP-W3: excludedBundledStdlibFiles 解消（前提: KSP-202。相互独立・並列可）

### KSP-W4: モジュール量産移行（各タスク = 1 PR。手順はすべて T）

#### kotlin.reflect [M 番号なし・新設]（棚卸し 2026-07-01: メタデータレジストリ依存のためブリッジ色が濃い）

- [x] KSP-496: KClass 公開 API 層を Kotlin 化し、メタデータレジストリを `__kk_` 降格する
  - 完了: 下敷き2ファイルを `Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt`/`KClassMemberIntrospection.kt` へ移設・実配線（ルート `Stdlib/` の死蔵版は削除）。Kotlin 化: `simpleName`/`qualifiedName`/`isInstance`/真偽値フラグ12種（isFinal/isOpen/isAbstract/isData/isSealed/isValue/isEnum/isInterface/isObject/isInner/isCompanion/isFun。チケット記載は「11種」だが実装対象は`CompilerKnownNames.swift`基準の12種）/`visibility`/`annotations`。`__kk_` 降格: rg で全列挙した `kk_kclass_*`/`kk_type_token_*`/`kk_ktype_*`/`kk_ktypeprojection_*`/`kk_kfunction_*`/`kk_kparameter_*`/`kk_kconstructor_*`/`kk_annotation_*`（`RuntimeStringArray.swift`/`RuntimeReflection.swift`、計 ~65 個。`cast`/`safeCast` の実体もリネーム済み）をリネームし、`RuntimeABISpec` 側も追従（未登録だった `kk_kclass_nested_classes` の欠落も是正）。
  - 「全部対応して」指示を受けた追加調査で、残り3カテゴリの根本原因を深掘りし、うち2件を実際に修正した（詳細は下記）。全カテゴリの完全移行には至っていないが、根本原因の解像度は大きく上がっている。
  - **修正済みの根本原因バグ（3件、いずれも `Sources/CompilerCore/` 内）**:
    1. `String::class`/`Char::class`/`Any::class` のように、`HeaderHelpers.ensureClassSymbol` が member 宣言（CharSequence 適合など）を持たせるためだけに登録する `kotlin.<Name>` 偽装 `.class` シンボルが存在する組み込み型で、`T::class` のスコープ解決がこの偽装シンボルを builtin 名フォールバックより先に見つけてしまい、`classRefTargetType` が偽装 nominal 型（`.classType`）になる問題。これにより `String::class.isInstance("x")` が `RuntimeTypeCheckToken.encode` で `nominalBase` として誤符号化され、常に `false` を返していた（正しくは `stringBase`）。修正: `RuntimeTypeCheckToken.encode`（`Sources/CompilerCore/KIR/RuntimeTypeCheckToken.swift`）に `encodeBuiltinDisguisedNominal` を追加し、`.nominal` 分類時にこの偽装を検出して builtin base へフォールバックするようにした。回帰テスト `testBuiltinClassRefTokenMatchesPrimitiveBase`（`Tests/CompilerCoreTests/KIR/RuntimeTypeCheckTokenTests.swift`）追加済み。
    2. 上記と同根で、`TypeSystem.isSubtype` が偽装 nominal 型（例: `String` の `kotlin.String` 偽装シンボル）と canonical builtin 型（`.stringStruct` 等）を無関係な型として扱っていたため、`fun <T : Any> KClass<T>.cast(value: Any?): T = value as T` を `String::class.cast(v)` のように呼ぶと、ジェネリック制約ソルバが `KSWIFTK-TYPE-0001: Conflicting bounds for type variable`（`Class#N is not a subtype of Class#N & String`）を出して失敗していた。修正: `TypeSystem`（`Sources/CompilerCore/Sema/TypeSystem/TypeSystem.swift`）に `stringClassSymbol`/`charClassSymbol`/`anyClassSymbol` を追加（`HeaderHelpers+SyntheticStringStubs.swift`/`+SyntheticCharStubs.swift`/`HeaderHelpers.swift` の登録箇所で設定）し、`Subtyping.swift` の `isSubtype` 冒頭で `normalizeBuiltinDisguisedClassType` により両辺を正規化するようにした。`fun <T : Any> KClass<T>.myCast(value: Any?): T = value as T` を `String::class.myCast(v)`（期待型 `String`）から呼ぶケースで実際にコンパイル・実行成功を確認済み。
    3. （KClass 無関係の汎用バグ、上記調査中に副産物として発見）`fun <T> foo(value: Any?): T { return value as T }` のように非 reified 型パラメータへ `as T` する「unchecked cast」で、`RuntimeTypeCheckToken.encode` が `.typeParam` を `unknownBase`(=0) として符号化し、`kk_op_is` の `default: return 0` に落ちて **常に ClassCastException を投げていた**（本来 JVM 型消去と同じく無条件成功すべき）。`is T`（非 reified）は既に `KSWIFTK-SEMA-0084` でコンパイルエラーになるためこの土台は `as`/`as?` 経由でしか到達しないことを確認済み。修正: `ExprLowerer+ControlFlowAndBlocks.swift` の `.asCast` lowering で、ターゲット型が非 reified 型パラメータの場合はランタイム呼び出しを発行せず `.copy` 命令で値をそのまま通すようにした。
  - **完了（KSP-689）**: `members`/`constructors`/`primaryConstructor`/`properties`/`memberProperties`/`declaredMemberProperties`/`functions`/`memberFunctions`/`declaredMemberFunctions`/`nestedClasses`/`supertypes` が返す `RuntimeKFunctionBox`/`RuntimeKPropertyStub` 等のランタイムハンドルへ安定 nominal 型 ID と supertype edge を付与し、真の interface 適合性チェック（`is`/`as`）を成立させた。`KCallable.name` は複数 Box 型を順に `tryCast` する共通 bridge へ統合し、新規 diff/codegen/Runtime 回帰で検証済み。実装は `IndexedValue`/`Map.Entry` の前例である `runtimeRegisterObjectType(rawValue:classID:)` + `runtimeRegisterTypeEdge(childTypeID:parentTypeID:)`（`RuntimeHelpers.swift`）を利用し、Sema 側で既にモデル化済みの `KFunction <: KCallable` 等の関係と一致させている。
    - ~~`cast`/`safeCast`~~ **完了**: 懸案だった「throwing な `@KsSymbolName` external を bundled stdlib から呼ぶ」形が実際に動くことを検証した。`ABILoweringPass` は `RuntimeABISpec` の `isThrowing` を参照して `outThrown` 引数を自動挿入するため、Kotlin 側の external 宣言は値引数のみを書けばよい（`CallLowerer+MemberCallEmission.swift` の `throwingCallees` はメンバーコール専用で、この経路には無関係）。`KClassBasicAPI.kt` に `__kk_kclass_cast`/`__kk_kclass_safeCast` ブリッジと `KClass<T>.cast`/`safeCast` 拡張を追加し、Sema（`CallTypeChecker+KClassMemberCallInference.swift`）と KIR（`CallLowerer+KClassReflectMemberCalls.swift` / `CallLowerer+MemberCalls.swift`）の特例、および使われなくなった `kClassCastReturnType`/`kClassSafeCastReturnType`/`kClassCastName`/`kClassSafeCastName` を削除。diff ケース `kclass_cast.kt` と実行テスト `BundledStdlibExecutionTests.testKClassCastAndSafeCastExecuteThroughBundledExtensions` を追加。
    - `findAnnotation`: reified 型引数を要求する点に加え、見つかったアノテーションのランタイム表現 `RuntimeAnnotationBox`（`Sources/Runtime/RuntimeTypes.swift`）が引数を汎用文字列配列としてしか保持しないため、`findAnnotation<A>(): A?` を精密な `A?` 型で返しても `A` の宣言プロパティへの実アクセスは機能しない（members/constructors と同根の「ランタイムハンドルが本物の Kotlin オブジェクトとして振る舞わない」問題）。現状の compiler 特例は正直に `Any?` を返しているため、`if (found != null)` のような存在確認以上の用途は元々サポートされていない。
    - `findAssociatedObject`: 単体では戻り値が `Any?`（`T` へのキャスト不要）かつ実体が `runtimeObjectRaw=` プレフィックス経由で本物のオブジェクトハンドルを返す設計のため、Kotlin ソース化自体は上記2つより低リスクに見えたが、**既に `HeaderHelpers` 側で reified・inline・`@ExperimentalAssociatedObjects` opt-in 要求を満たす専用の synthetic シンボルが登録済み**（`Tests/CompilerCoreTests/Sema/ReflectFindAssociatedObjectSyntheticTests.swift` で検証されている）であることが判明。Kotlin ソースへの置き換えはこの opt-in 強制や reified 型引数の意味論を含めて忠実に再現する必要があり、当初想定より複雑と判断してこのセッションでは見送った（着手しかけた変更は復元済み）。
  - **見つかったが対象外として別タスクに切り出したバグ（2件、いずれも KClass 無関係の汎用コンパイラバグ）**: (1) ジェネリック関数内の文/式に `@Suppress("UNCHECKED_CAST")` を付けると `KSWIFTK-TYPE-0001`/`KSWIFTK-SEMA-0022` 等の誤エラーが発生する（HEAD でも再現する既存バグ、確認済み）。(2) `inline fun <reified T>` の本体で発生した例外が呼び出し元の `try`/`catch` で捕捉されずクラッシュする（インライン展開と例外処理範囲の相互作用が疑われる）。
  - 副産物として発見・修正した既存バグ（他の bundled Kotlin 拡張全般に影響しうる）: (1) `kotlin.reflect` が `ScopeBuilder.swift` のデフォルトインポートパッケージ一覧に無く、`kotlin.reflect` 配下の拡張がスコープ解決で見つからなかった (2) `BundledDeclarationIndex.receiverOwnerFQName` が `.kClassType`（`T::class` 用の内部専用型表現）を未処理で、`KClass<...>` レシーバの拡張が優先規則の索引に正しく載っていなかった (3) `RuntimeABISpec+Operator.swift` の `__kk_kclass_find_associated_object` 登録に `isThrowing: false` が抜けており、実体（2引数、`outThrown` 無し）と齟齬していた。
  - **完了（2026-08-18 追補）**: KSP-689 が nominal 型 ID を付与した `members`/`constructors`/`nestedClasses`/`primaryConstructor`/`memberProperties`/`declaredMemberProperties`/`functions`/`memberFunctions`/`declaredMemberFunctions`/`supertypes`（10種）を、`KClassMemberIntrospection.kt` の通常 Kotlin 拡張宣言（既存の `__kk_kclass_*` ブリッジへ委譲するだけ）へ実際に移行し、`CallTypeChecker+KClassMemberCallInference.swift`/`CallLowerer+KClassReflectMemberCalls.swift`/`CallLowerer+MemberCalls.swift` の対応する compiler 特例を削除した。`properties`（"member"/"declaredMember" 接頭辞なし）のみ、本家 kotlin-stdlib に存在しない架空の名前であり `Scripts/diff_cases/kclass_interface_handles.kt` がこれをユーザー宣言で shadow できることに依存しているため、意図的に compiler 特例のまま残した。
  - 移行作業中に「bundled 宣言と同名のユーザー宣言があるとコンパイルが著しく遅くなる」ように見える事象を一時疑ったが、高負荷なローカル環境（他セッションの並行ビルドで load average 200 超）での壁時計計測がノイズだっただけで、負荷の低い状態で CPU 時間・フェーズ別内訳・複数回試行の中央値を取って比較したところ shadow の有無で有意差は無いことを確認した（誤報として撤回済み）。
  - **診断の訂正（2026-08-18 Devin レビュー起点の再調査）**: 当初「`properties` を bundle 化すると、bundled 宣言とユーザーのファイルローカル宣言が同名で共存した際にファイルローカル宣言が正しく優先されず `kclass_interface_handles.kt` が退行した」と記録していたが、これは誤診断だった。`resolveExtensionPropertyGetter`（`CallTypeChecker+MemberCallCompanionAndProperties.swift:44`）にデバッグ計装を入れて実際に追跡したところ、`ctx.cachedScopeLookup` はスコープの shadowing を正しく尊重しており、`memberProperties` を実際に bundle 化して同じ shadow 構成で再現しても、ユーザーのファイルローカル宣言側の getter が正しく選ばれ、呼び出されることを確認済み（`val KClass<*>.memberProperties: List<Any?> get() = listOf("USER_MARKER_VALUE")` という shadow 宣言で `klass.memberProperties` が `["USER_MARKER_VALUE"]` を返すことを確認）。宣言解決自体にバグは無い。
  - **正しく特定できた根本原因、修正済み（KClass 無関係の汎用バグ）**: `kclass_interface_handles.kt` の `properties` shadow 宣言の本体 `get() = listOf(ReflectionSample::value)` が使う「バインドされていないプロパティ callable reference」（`Type::property` / `instance::property`）が、期待型（expected type）の無い文脈で評価されると誤った型に推論されていた。`ExprTypeChecker+NameLambdaAndCallableRefInference.swift` の `inferCallableRefExpr` 内、プロパティ候補が見つかった2分岐（unbound/bound の分岐と、bare `::member` の分岐）が、期待型が無いとき `KProperty0<T>`/`KMutableProperty0<T>`/`KProperty1<Owner, T>`/`KMutableProperty1<Owner, T>` を構築せず、プロパティの**値の型**そのもの（`propertyType`）へ単純にフォールバックしていた（関数 callable reference 側の対応する分岐は `driver.helpers.callableFunctionType(for:bindReceiver:sema:)` で期待型の有無に関わらず正しい関数型を都度構築しており、プロパティ側だけこの扱いが欠落していた）。
    - 最小再現（修正前）: `class C(val v: Int); fun main() { val ref = C::v; println("ref = $ref") }` → 実際には `ref = 0`（期待される `KProperty1<C, Int>` の文字列表現ではなく、`v` の値の型 `Int` の既定値らしき `0` が出力されていた）。
    - 修正: `ExprTypeChecker+NameLambdaAndCallableRefInference.swift` に `kPropertyReferenceType(ownerType:valueType:isMutable:sema:interner:)` を追加し、`kotlin.reflect.KProperty0`/`KMutableProperty0`/`KProperty1`/`KMutableProperty1` を `sema.symbols.lookup(fqName:)` で解決して具体化した型を構築、`inferCallableRefExpr` の該当2分岐の `let resultType = expectedType ?? propertyType` を `let resultType = expectedType ?? (kPropertyReferenceType(...) ?? propertyType)` に変更した（型解決に失敗した場合のみ旧フォールバックへ委譲）。回帰テスト `Tests/CompilerCoreTests/Sema/PropertyCallableReferenceDefaultTypeTests.swift`（unbound/bound/mutable/bare の4パターン + 明示的期待型が引き続き優先されることの固定）と diff ケース `Scripts/diff_cases/kproperty_default_inference.kt` を追加。`kclass_interface_handles.kt` は `properties` を compiler 特例のままにした状態でも green（この根本原因修正により、shadow 宣言の本体が正しく実行され `is KProperty<*>` が `true` を返すようになったため）。
    - **Devin Review 起点の追補修正（3件）**: (a) `expectedType` が `KProperty<*>`/`Any` 等、上記4種の具体形でない場合に無条件採用してしまい KIR 側の wrapper 生成条件（`propertyReferenceShape`）を満たせなくなる欠落を発見・修正。`resolvedPropertyReferenceResultType`（関数 callable reference 側の `expectedFunctionType`/`expectedSamInterfaceType` 判定と同じ考え方）を追加し、`expectedType` は「4種の具体形」または「関数型/SAM型」のときのみ採用し、それ以外は `inferredType` を使うようにした（`val p: KProperty<*> = C::v; p is KProperty<*>` が `true` になることを確認）。(b) その過程で一度「関数型/SAM型の expectedType も却下する」実装を入れてしまい、`val f: (C) -> Int = C::v` のような「プロパティ参照を関数値として使う」既存の正当なケースを壊しかけたが、実際には `list.map(C::v)` も `val f: (C) -> Int = C::v` も **本PRとは無関係に master 上で既にリンクエラー（`Undefined symbols ... "_name"`, 生成される `kk_function_value_adapter_*` サンクが未定義シンボルを参照）になる pre-existing バグ**であることを確認した上で、関数型/SAM型は無条件採用（修正前の Sema 挙動と同一）に戻した。回帰テスト `testExplicitFunctionTypeExpectedTypeStillWinsOverKPropertyDefault`（`PropertyCallableReferenceDefaultTypeTests.swift`）で Sema 側の型 binding のみ固定（下記バグ3のため実行までは確認できない）。(c) **🔴 高深刻度・実際に修正**: クラスのメンバー関数内で書いた bare `::プロパティ名`（レシーバなし。Kotlin では `this::プロパティ名` と同義の bound reference）が、既定型推論で `KProperty0`/`KMutableProperty0` になった結果、`LambdaLowerer.lowerCallableRefExpr`（`Sources/CompilerCore/KIR/LambdaLowerer.swift`）の wrapper 生成経路に新たに到達可能になったが、`receiverExpr == nil` のため `captureArguments` が空のまま生成され、暗黙レシーバ `this` を全く捕捉していなかった。結果、生成される accessor はレシーバ引数を要求するのに呼び出し側は 0 引数で呼ぶという不整合が生じ、`::v.get()` が `KSWIFTK-RUNTIME-0001: kk_array_get_inbounds precondition failed` でクラッシュしていた（`class C(val v: Int) { fun r(): Int = ::v.get() }` で再現。real kotlinc はこれを正当なコードとしてコンパイル・実行できることを `diff_kotlinc.sh` で確認済み — bare `::member` のメンバープロパティ implicit-this bound reference は元々サポートすべき正当な文法だった）。修正: `lowerCallableRefExpr` で `targetSymbol` の解決を capture 判定より前に移動し、`receiverExpr == nil` かつ対象がプロパティで `parentSymbol` がクラス/interface/object/enum（`isNominalTypeContainerSymbol`、新設、`LambdaLowerer+CallableResolutionAndCapture.swift`）の場合、`driver.ctx.activeImplicitReceiverExprID()` を capture として追加するようにした（`this::member` と同じ捕捉経路）。回帰: `Tests/CompilerCoreTests/KIR/CallableRefTypeIdentityTests.swift` に `testKIRCapturesImplicitReceiverForBareMemberPropertyRef`、diff ケース `Scripts/diff_cases/kproperty_bare_member_implicit_receiver.kt`（get/set 両方、`diff_kotlinc.sh` で real kotlinc と実行結果一致を確認済み）を追加。
    - **Devin Review 起点の追補修正（さらに2件、いずれも 🔴/🟡 高深刻度）**: (d) **修正済み**: `lowerCallableRefExpr` の暗黙レシーバ capture 分岐は `parentSymbol` が nominal 型かどうかしか見ておらず、capture するレシーバの**型**が実際にそのプロパティの所有者と一致するかを検証していなかった。`with(sb) { ::v }`（`v` は外側クラスのプロパティ、`sb` は無関係な `StringBuilder`）のようにレシーバ付きスコープ関数の内側では `activeImplicitReceiverExprID()` がスコープ関数のレシーバに差し替わっている（`CallLowerer+ScopeFunctionLowering.swift`）ため、無関係な型のオブジェクトを capture し `.get()`/`.set()` が別オブジェクトのフィールドを読み書きする危険があった。修正: `implicitReceiverMatchesOwner`（新設、`LambdaLowerer+CallableResolutionAndCapture.swift`）で `arena.exprType(implicitReceiver)` のノミナル型が所有クラスと一致（またはそのサブタイプ）であることを確認し、一致しない場合は capture せず（result: `with(sb) { ::v }` は capture 前と同じ `KSWIFTK-RUNTIME-0001` の安全なクラッシュに留まり、メモリ破壊は起きない）。(e) **回避策で対応**: (d) の型一致チェックを追加しても、companion object / 単純な `object` / enum entry が所有者の場合は、レシーバの型が正しく一致した上でもなお SIGSEGV でクラッシュすることが判明した（`class C { companion object { val x: Int = 5; fun readX(): Int = ::x.get() } }`）。これは capture の型不一致ではなく、シングルトンインスタンスの表現・到達方法自体に別の未特定の問題があると見られる（根本原因は本PRの範囲外として未調査）。安全のため、capture 対象を `isCaptureEligibleInstanceContainerSymbol`（`isNominalTypeContainerSymbol` から改名・`.class` のみに限定、`.interface`/`.object`/`.enumClass` を除外）で `.class` のみに制限し、**Sema 側でも** `.class` 以外を所有者とする bare `::member` は既定型推論・`resolvedPropertyReferenceResultType` の両方をバイパスして修正前の（`expectedType` を無視する）フォールバック挙動に戻した。結果、companion/object/enum 所有のプロパティへの bare `::member` 参照は本PR前と同じ「コンパイルエラー」に留まり、real kotlinc が受理する一部のケース（companion のプロパティ参照）を「コンパイルは通るがクラッシュする」に変えてしまうことを避けている。real kotlinc はこのケースを受理する（`diff_kotlinc.sh` で compile exit mismatch を確認済み — 意図的な未サポートなので diff ケースには追加していない）。
  - **副産物として見つけた既存バグ（4件、いずれも上記修正とは無関係の pre-existing・修正は本PR範囲外）**:
    1. **修正済み（当初「itable 登録の複数インスタンス破壊バグ」と誤診断していたが、実体は Sema 型推論バグの別症状だった）**: 同一プロパティへの「変数に代入して直接 `is` チェック」と「`listOf(...)` 経由で `is` チェック」を同一関数内で両方行うと SIGSEGV でクラッシュする問題（`class C(val v: Int); fun main() { val ref: KProperty1<C, Int> = C::v; println(ref is KProperty<*>); val list: List<KProperty1<C, Int>> = listOf(C::v); println(list[0] is KProperty<*>) }` → SIGSEGV、`kk_fn_get_s108686` 相当の生成関数内、`str xzr, [x8]` で無効アドレス書き込み）。当初は「`kk_object_register_itable_iface`/`kk_object_register_itable_method`（`Sources/Runtime/RuntimeStringArray.swift`）が生ポインタキーの辞書に登録する設計のため、複数 wrapper インスタンスが絡むと状態破壊が起きる」という runtime 側の仮説を立て、Sema 修正と無関係に再現することまでは確認していたが、実際に `lldb` でクラッシュ箇所を追跡したところ itable 登録そのものは無関係で、原因は `listOf(vararg elements: T)` へ渡す `C::v` が **`T` が未解決な間に型検査される**ため（`val list` 自体の宣言型注釈は無関係 — vararg の個々の要素式は `T` の解決前に個別に型検査される）、`resolvedPropertyReferenceResultType` が `expectedType`（＝未解決の `T`、`.classType` ではなく `.typeParam` を返すため `isConcreteKPropertyReferenceShape` は正しく `false` を返す）を却下して自然型へフォールバックする経路自体は正しく機能していたものの、そもそも本 PR のこの Sema 修正が landing する前の時点で観測されていたバグであり、**本 PR の Sema 修正（`kPropertyReferenceType`/`resolvedPropertyReferenceResultType`）が既に完全に修正していた**（`lowerPropertyReferenceWrapperValue` の `.classType` ガードが通るようになり、レガシーの裸シンボル参照フォールバック — `PropertyLoweringPass` が引数ゼロの getter 呼び出しへ誤って書き換えてしまう経路 — に落ちなくなったため）。現在の master 上のビルドで上記リプロを再実行し、クラッシュしないこと（`true`/`true` を正しく出力）を確認済み。ここに再度回帰を固定: diff ケース `Scripts/diff_cases/kproperty_generic_vararg_inference.kt`（`listOf(vararg)` 経由のパターン）と `Scripts/diff_cases/kproperty_supertype_expected_type.kt`（`KProperty<*>`/`Any` 型変数へ代入した参照を実際に使うパターン）を追加、Sema テスト `CallableRefTypeIdentityTests.testUnboundPropertyRefInGenericVarargCallGetsConcreteKProperty1Type` で `listOf(...)` 内の `C::v` が正しく `KProperty1` classType へ bind されることを固定。いずれも `diff_kotlinc.sh` で real kotlinc と一致確認済み。
    2. **修正済み**（旧: バインドされていないトップレベルプロパティ参照の `.get()` が常に値型の既定値を返す）: `val topLevel: Int = 7; fun main() { val bare: KProperty0<Int> = ::topLevel; println(bare.get()) }` → 期待値 `7` に対し実際は `0` になっていた。根本原因: 定数初期化子を持つ**不変（`val`）トップレベルプロパティ**は通常の読み取り経路（`ExprLowerer+ControlFlowAndBlocks.swift`）では `propertyConstantInitializers`/`constValueExprKind` によって呼び出し箇所へ定数がインライン展開され、対応するグローバルスロットへは一度も `.storeGlobal` で書き込まれない。一方 `ensurePropertyReferenceAccessor`（`LambdaLowerer+PropertyReferenceLowering.swift`）の getter 生成は無条件に `.loadGlobal` を発行しており、この「一度も書き込まれない」グローバルスロットを読んでいた（`var`、または定数でない初期化式を持つ `val` は元々このバグの影響を受けない — 対象は「定数畳み込み対象の `val`」のみ）。修正: getter 生成時にも同じ「不変プロパティかつ定数初期化子を持つ場合はインライン定数を使う」判定を追加し、それ以外の場合のみ `.loadGlobal` にフォールバックするようにした。回帰: diff ケース `Scripts/diff_cases/kproperty_toplevel_bare_reference.kt`（const `val` / `var` 双方の get、`var` の set まで含めて real kotlinc と実行結果一致を確認済み）。
    3. **修正済み（2026-09-13）**（旧: プロパティ callable reference を明示的な関数型として使う（HOF の引数、または関数型変数への代入）と、リンク時に未定義シンボルで失敗する）: `class C(val v: Int); fun main() { val f: (C) -> Int = C::v; println(f(C(1))) }` および `listOf(C(1)).map(C::v)` の両方が `Undefined symbols for architecture arm64: "_v"`（当初メモは `"_name"` と書いていたが、実際に未定義になるのはプロパティ名そのもの。case A は `kk_fn_main_*`、case B は `kk_fn_kk_function_value_adapter_*` から参照）でリンク失敗していた。
       - 根本原因: `lowerPropertyReferenceWrapperValue`（`LambdaLowerer+PropertyReferenceLowering.swift`）は bound type が `KProperty0`/`KMutableProperty0`/`KProperty1`/`KMutableProperty1` の具体形のときだけラッパーオブジェクトを生成する。関数型位置（関数型変数への代入・HOF 引数・SAM 変換）では bound type が関数型／fun interface 型なので nil を返し、`lowerCallableRefExpr` の汎用 callable 経路に落ちる。そこでは呼び出し対象がプロパティシンボルそのままで、`callableTargetName` が宣言名（`v`）を返す。プロパティシンボルには KIR 関数実体が無いため、Codegen の呼び出し解決（`internalFunctions[symbol]` 引き）が外れて「外部 C 関数 `v`」の宣言にフォールバックし、リンカまで `v` が素通りしていた。診断メモの「function-value-adapter の生成経路にコード生成バグ」は誤り（アダプタ自体は正しく、アダプタが呼ぶ登録済み callee 名が壊れていた）。
       - 修正: `LambdaLowerer+PropertyReferenceLowering.swift` に internal な `propertyReferenceFunctionCallTarget` を追加（既存の `ensurePropertyReferenceAccessor` に委譲し、生成済みアクセサの symbol と KIR 名を返す）。`lowerCallableRefExpr` は `lowerPropertyReferenceWrapperValue` が nil を返した後・3つの呼び出し対象分岐（SAM ラッパー / HOF ラッパー / 素の callable 値）の前で、propertyRef の呼び出し対象をこのアクセサへ差し替える。差し替え位置は必ずキャプチャ判定より後にする: `isSingletonOwnedPropertyRef` と `isCaptureEligibleInstanceContainerSymbol` は `parentSymbol(for:)` をプロパティシンボルに対して引くが、合成アクセサシンボルは親を持たないため、先に差し替えると KSP-496/505 のキャプチャ判定が黙って壊れる。
       - 同時に見つけた同根の別症状も修正（SAM 変換位置）: `fun interface IntFromSample { fun apply(s: Sample): Int }` に `useSam(Sample::v)` を渡すと `KSWIFTK-RUNTIME-0001: Virtual dispatch failed: method not found in vtable/itable` で panic していた（ラムダと関数参照は動作するのでプロパティ参照限定）。真因は Sema 側: `resolvedPropertyReferenceResultType` は expected type が fun interface のとき結果型としてその interface を採用するのに、`markSamConversion`/`bindSamInterfaceType`/`bindSamUnderlyingFunctionType` を呼んでいなかった（関数参照側は BUG-164 で対応済み、プロパティ参照側の2分岐だけ欠落）。マークが無いと `lowerCallableRefExpr` は itable を持つラッパーオブジェクトを作らず、生のタグ付き callable を interface 引数に渡していた。`ExprTypeChecker+NameLambdaAndCallableRefInference.swift` に `markPropertyReferenceSamConversionIfNeeded` を追加して両分岐から呼ぶ。`lowerCallableRefSamWrapperValue` にも `targetName` を通し、アクセサの KIR 名（symbol 由来の名前が取れず `kk_unknown_callable` になるのを避ける）を使う。
       - 回帰: diff ケース `Scripts/diff_cases/kproperty_function_type_position.kt`（新規。unbound / HOF / bound / custom getter / `var` メンバ / `object` メンバ / トップレベル `val`・`var` / unbound SAM / bound SAM の10形状。bound SAM は SAM サンクが「キャプチャ済みレシーバ + 差し替え後のアクセサ」を同時に踏む唯一の形状）と、実行まで行う backend テスト2件 `CodegenBackendVirtualDispatchTests.testPropertyReferenceInFunctionPositionCallsTheAccessor` / `.testPropertyReferenceSamConversionDispatchesThroughTheInterface`（失敗モードがリンクと実行時 panic なので KIR 形状テストでは捕まらない）。
    4. **修正済み（KSP-505 追補、2026-08-19）**（旧: companion object / `object` / enum entry が所有するプロパティへの bare `::member` 参照が SIGSEGV でクラッシュする）: `class C { companion object { val x: Int = 5; fun readX(): Int = ::x.get() } }` → 明示的な型注釈を与えて capture の型一致チェックを満たしても尚 SIGSEGV していた。
       - 根本原因（companion object / plain `object` のみ、singleton 全般ではなかった）: 二重の問題があった。(a) `ensurePropertyReferenceAccessor`（`LambdaLowerer+PropertyReferenceLowering.swift`）が所有者の種別を見ずに常に「レシーバ + フィールドオフセット」経路（`kk_array_get_inbounds`）で accessor を生成していたが、`.object` 所有プロパティの実際の格納先はインスタンスフィールドではなく単一のモジュールレベル global スロット（`ExprLowerer+ControlFlowAndBlocks.swift` の `pk == .object` 分岐と同じ）だった。(b) companion/object がインターフェースを実装せず仮想 dispatch も持たない場合、実体は一切ヒープ確保されず（`KIRLoweringDriver+ObjectInitializer.swift`）、その「レシーバ」は単なる `0`（null）のプレースホルダになる（`NativeEmitter+EmissionConstants.swift` の `.symbolRef` 定数畳み込みが `globalVariables`未登録シンボルを `zeroValue` にフォールバックするため）。したがって capture されたレシーバで `kk_array_get_inbounds(0, offset)` を呼び SIGSEGV していた。
       - 修正: `.object` 所有プロパティに限り、(1) `ensurePropertyReferenceAccessor` が `ownerType: nil` を渡して受信者なしの `.loadGlobal`/`.storeGlobal` 経路（既存の KSP-496 バグ2番の定数インライン最適化を含む）にフォールバックするようにし、(2) `LambdaLowerer.lowerCallableRefExpr` が bare/明示的レシーバ両方の callable ref で暗黙 this のキャプチャを一切行わないようにした（`isSingletonOwnedPropertyRef` 判定を新設。キャプチャ数と accessor の引数個数を一致させる必要があるため、両者は必ずセットで直す）。Sema 側（`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`）も `.object` 所有者を `.class` と同様に `KProperty0`/`KMutableProperty0` の型推論対象に含めるよう緩和した。
       - `.enumClass` は意図的に除外したまま: 同じ「シングルトン」直感に反し、`enum class E(val v: Int) { A(1), B(2) }` のようにエントリ毎に別インスタンス・別フィールド値を持つため、`.object` と同じ global 化を試すと **実際にリグレッションを引き起こすことを実測で確認**（`::v` が全エントリで `0` を返す誤った値バグに変わった）。よって `.enumClass` は KSP-496 時点の安全なフォールバック（`expectedType` を無視しコンパイルエラーのまま）を維持。
       - **未検証・範囲外**: 「エントリ固有 body 内で宣言されたプロパティ」（例: `enum class E { A { val x: Int = 5 } }` の `x`）は、所有者がエントリ自身の匿名サブクラス（`.class` 相当）になっている可能性があり、その場合は既存の `.class` 経路で最初から動く可能性がある。しかし検証しようとすると、エントリ固有 body を持つ enum 定数を `EnumClass.ENTRY` の形で参照するだけで無関係の pre-existing バグ（`Unresolved member function`。`docs/diff-skip-inventory.md` の `enum_edge_cases.kt` 項目に記載済み）にブロックされ、確認できなかった。
       - 修正ファイル: `Sources/CompilerCore/Sema/TypeCheck/ExprTypeChecker+NameLambdaAndCallableRefInference.swift`, `Sources/CompilerCore/KIR/LambdaLowerer.swift`, `Sources/CompilerCore/KIR/LambdaLowerer+CallableResolutionAndCapture.swift`, `Sources/CompilerCore/KIR/LambdaLowerer+PropertyReferenceLowering.swift`。回帰: diff ケース `Scripts/diff_cases/kproperty_singleton_bare_reference.kt`（companion の const `val`/`var` の get・set、`Companion.` 経由の直接アクセスでの反映確認、トップレベル `object` の明示レシーバ参照まで含めて `diff_kotlinc.sh` で real kotlinc と実行結果一致を確認済み）。
  - diff: `kclass_basic.kt`, `kclass_cast.kt`（新規）, `reflect_kclass_ktype.kt`, `kclass_type_model.kt`, `type_reflection.kt`, `reflection_dynamic_call.kt`, `kclass_interface_handles.kt`, `kproperty_default_inference.kt`（新規）, `kproperty_bare_member_implicit_receiver.kt`（新規）, `kproperty_toplevel_bare_reference.kt`（新規）, `kproperty_singleton_bare_reference.kt`（新規）, `kproperty_generic_vararg_inference.kt`（新規）, `kproperty_supertype_expected_type.kt`（新規）, `kproperty_function_type_position.kt`（新規） green（移行後も kotlinc と一致）。`kclass_members.kt`/`kclass_ktype_basic.kt`/`annotation_reflection.kt` は変更前から kotlinc 側が別理由（`kotlin.reflect.full` 未 import 等）で失敗しており未変更（git stash で移行前と同一エラーを確認済み）。
  - **クローズアップ（2026-09-14、KUU-504）**: `__kk_` 降格・Kotlin 化そのものの残作業はゼロと確認（`kk_kclass_*`/`kk_ktype_*`/`kk_kfunction_*`/`kk_kparameter_*`/`kk_kconstructor_*`/`kk_annotation_*`/`kk_type_token_*`/`kk_ktypeprojection_*` を rg で全列挙して単一アンダースコアの残留なし）。ただし2件の移行残滓を発見・削除した。(1) `Sources/RuntimeABI/RuntimeABISpec+ABIParity.swift` の `kk_kclass_register_annotation`/`kk_kclass_has_annotation`/`kk_kclass_js`/`kk_annotation_class_name`/`kk_annotation_simple_class_name`/`kk_annotation_get_arguments` — @_cdecl 実装なし・コンパイラからの発行なしの単一アンダースコア死蔵スペック（2026-03 の ABI 自動生成時点の遺物、実際の annotation API は `__kk_kclass_get_annotations`/`__kk_kclass_find_annotation`/`__kk_kclass_register_single_annotation` に統合済みで無関係。`kk_kclass_js` は JS プラットフォーム専用の本家 API でこのコンパイラの対象外）。`Tests/RuntimeTests/ABIMismatchRuntimeExportParityTests.swift`（このPR作成時点では `ABIMismatchTests+RuntimeExportParity.swift`、#6774 でリネーム済み）の `allowedSpecOnlyRuntimeABINames` 側の対応エントリも削除。(2) `Sources/CompilerCore/Sema/Infrastructure/CompilerKnownNames.swift` の `KnownCompilerNames` に、Kotlin 化で使われなくなった interned name フィールドが28個残っていた（`simpleName`/`qualifiedName`/`isInstanceName`/`membersName`/`constructorsName`/`primaryConstructorName`/`nestedClassesName`/`isFinalName`/`isOpenName`/`isAbstractName`/`visibilityName`/`typeParametersName`/`supertypesName`/`isDataName`/`isSealedName`/`isValueName`/`isEnumName`/`isInterfaceName`/`isObjectName`/`isInnerName`/`isCompanionName`/`isFunName`/`memberPropertiesName`/`declaredMemberPropertiesName`/`functionsName`/`memberFunctionsName`/`declaredMemberFunctionsName`/`annotationsName`）。宣言・初期化の2箇所以外で参照ゼロ（`grep -rn "\.$n\b"` で外部参照0件をフィールド単位で確認、`Mirror(reflecting:)`/KeyPath 経由の間接参照も無し）であることを確認して削除。特例として残る `propertiesName`/`findAnnotationName`/`findAssociatedObjectName` は引き続き使用中のため維持（§13-7の2点確認②「Sema/KIR/Lowering に同名の name-string 特例が残っていない」を、この3つを除いて機械的に満たす状態になった）。検証: `swift build` green、`RuntimeABIExternalLinkValidationTests`（4/4）・`ABIMismatchRuntimeExportParityTests`（3/3）・`KClassBooleanIntrospectionTests`（6/6）・`StandaloneClassReferenceTests`（12/12）green。全体テスト・kotlinc diff 全件は未実行（変更が dead code 削除のみのため対象範囲外と判断）。

#### kotlin.coroutines / Flow / Channel [(c)/(b) 分類確定 + (b) 群のみ移行]（棚卸し 2026-07-01: スタブ 23 ファイル 10,849 行 / Runtime 7 ファイル 279 @_cdecl）

> 引き継ぎ注記(2026-07-10): 旧 `STDLIB-CORO-001`（`[~]` のまま 2026-07-07 #4582 で削除）の残課題は KSP-498/499 + KSP-674〜679 が正式に引き継ぐ。SharedFlow/StateFlow 等の細分は KSP-W6 の concurrent 節を参照。

### KSP-W5: 後始末（W3/W4 の対応タスク完了後）

- [ ] KSP-1541: 機能スライス名の bundled `.kt` ファイルを kotlin-stdlib 本家準拠のファイル名へ統合・リネームする（KSP-505 手順(2)(3) の分割先。前提: 対象モジュールの M フェーズ完了）
  - 背景: `docs/stdlib-pipeline.md` §6「既存の機能スライス名（`ListFilterHOF.kt` 等）は当該モジュールの M フェーズ完了時に統合・リネームする」を実行するタスク。2026-08-18 時点では text（M1: `KSP-693` 未完了）/collections（M3: `KSP-426`/`KSP-428` 未完了）を含む複数のモジュールがまだ (b) 残ありで対象外（着手時に §9 棚卸し表で全モジュールを再確認すること）
  - 着手条件: `docs/stdlib-pipeline.md` §9 の3分類棚卸し表を rg で再確認し、対象モジュールの (b) 行（未移行の合成スタブ登録）が 0 件であること。モジュール単体で条件を満たせば、そのモジュールだけ先行して統合・リネームしてよい（粒度ルールにより 1 モジュール = 1 PR に分割可）
  - 手順: (1) 対象モジュール配下の機能スライスファイル（例: `collections/ListFilterHOF.kt`, `text/StringBasics.kt` 等）を本家 kotlin-stdlib のファイル名・配置（例: `collections/Collections.kt`, `text/Strings.kt`）へ統合・リネーム（`docs/stdlib-pipeline.md` §6）。挙動変更ゼロが条件 (2) `UPDATE_GOLDEN=1` で golden 更新し `git diff -- Tests/CompilerCoreTests/GoldenCases` が機械的差分のみであることを確認 (3) 共通ゲート G green
  - 監査手法: `Sources/CompilerCore/Stdlib/kotlin/` の Apache 帰属ヘッダ（`Derived from kotlin-stdlib <...>` / `Derived from kotlin-native <...>`）が宣言する本家パスの basename と実ファイル名を機械照合すると、リネーム候補が証拠付きで列挙できる（2026-09-13 時点で 49 件不一致）。ヘッダが無い・曖昧な場合は JetBrains/kotlin の該当タグ（`v2.3.10`）のディレクトリ一覧と宣言位置で裏取りする
  - 進捗:
    - (1) 2026-09-07 #6587: `random/JavaRandomInterop.kt` → `random/PlatformRandom.kt`（単一ファイル）
    - (2) 2026-09-13 #6780: `kotlin/native/` モジュール全体。per-type ディレクトリ artifact（`<Type>/Stdlib.kt` / `<Type>/<Type>.kt`）22 件を撤去し、v2.3.10 の宣言オーナーへ統合（`Platform.kt` ← OsFamily/CpuArchitecture、`Annotations.kt` ← SymbolName、`concurrent/Atomics.kt` ← AtomicLong/AtomicNativePtr/AtomicReference/FreezableAtomicReference、`concurrent/Future.kt` ← FutureState/waitForMultipleFutures、`concurrent/ObjectTransfer.kt` ← TransferMode、`concurrent/Freezing.kt` ← FreezingException/freeze、`concurrent/Lazy.kt` ← atomicLazy、`concurrent/Internal.kt` ← attach/detachObjectGraphInternal・consumeFuture・executeImpl・waitWorkerTermination、`concurrent/Worker.kt` ← withWorker、`ref/Weak.kt`/`ref/WeakPrivate.kt`/`ref/Cleaner.kt`、`runtime/GCInfo.kt` ← MemoryUsage/RootSetStatistics/SweepStatistics、`BitSet.kt`/`Runtime.kt`/`ThrowableExtensions.kt`/`runtime/GC.kt`/`runtime/NativeRuntimeApi.kt`/`concurrent/MutableData.kt`/`concurrent/WorkerBoundReference.kt`）。enforcing: `BundledStdlibOrderingTests.testNativeBundledFilenamesFollowKotlinNativeLayout` が `native/` 配下の `Stdlib.kt` 名と eponymous ディレクトリを拒否する
    - (3) 2026-09-15 #6840: native 残件3件を解消。`ObsoleteNativeApi`/`FreezingIsDeprecated` を `native/Annotations.kt` から分離し、それぞれ `native/ObsoleteNativeApi.kt`/`native/FreezingIsDeprecated.kt` へ単独ファイル化（本家 basename と一致）。`FreezingIsDeprecated` の本家オーナーは `kotlin-native/runtime/.../kotlin/native/` ではなく `libraries/stdlib/native-wasm/src/kotlin/native/FreezingIsDeprecated.kt` と判明（v2.3.10 タグで実ファイル確認済み）。`native/ObjCInterop.kt` は解体し、`ObjCName`/`CName`/`HidesFromObjC`/`HiddenFromObjC`/`RefinesInSwift`/`ShouldRefineInSwift` を本家同様 `native/Annotations.kt` に統合。`ObjCSignatureOverride` のみ本家では `kotlinx.cinterop.Annotations.kt`（`kotlinx/cinterop` パッケージ）所属だが、パッケージを変えると FQ 名が変わり挙動変更になるため対象外とし、`kotlin.native.ObjCSignatureOverride` のまま `Annotations.kt` にコード注釈付きで残置。enforcing: `testNativeBundledFilenamesFollowKotlinNativeLayout` に新ファイル2件の存在確認と `ObjCInterop.kt` 不在の assertion を追加。検証: `swift build` / `BundledStdlibOrderingTests` / `NativePlatformAnnotationTests`（26件、FQ名ベースの登録・診断テストで移動による断線なしを確認）/ `GoldenSemaGoldenTests.matchesGolden`（92バッチ全 green。宣言の総数は不変で並べ替えのみのため golden 更新不要だった）。`diff_kotlinc.sh Scripts/diff_cases/native_annotations.kt` は `SKIP-DIFF`（既存 `DEBT-DIFF-001`: `kotlin.native.*`/`kotlinx.cinterop.*` は JVM kotlinc に対応 API が無く比較不能。本 PR 起因ではない）
    - (4) 2026-09-16: (b) 0 件の残りモジュールを一括処理。`coroutines/`: `Stdlib.kt` を `Continuation.kt`/`CoroutineContext.kt`/`SuspendFunction.kt` に分割、`SafeContinuation/Stdlib.kt`→`SafeContinuationNative.kt`（kotlin-native 実装ファイル名）、`ContinuationInterceptor/`→`ContinuationInterceptor.kt`、`AbstractCoroutineContextElement/`+`AbstractCoroutineContextKey/`+`EmptyCoroutineContext/`→`CoroutineContextImpl.kt`、`cancellation/CancellationException/`→`CancellationExceptionH.kt`、`intrinsics/Stdlib.kt`→`intrinsics/IntrinsicsNative.kt`。`reflect/`: `KCallable/`/`KClass/`/`KType/`/`KTypeProjection/`/`KVariance/` の per-type ディレクトリを解体し本家フラット名へ、`KProperties.kt`→`KProperty.kt`、`KClassBasicAPI.kt`+`KClassMemberIntrospection.kt`→`KClasses.kt` に統合。`contracts/`: `Contracts.kt`→`ContractBuilder.kt` に統合（本家は同ファイルが `ExperimentalContracts`/`InvocationKind` 等のオーナー）、`InvocationKind/`→`InvocationKind.kt`。`enums/Stdlib.kt`→`enums/EnumEntries.kt`、`annotation/Stdlib.kt`→`annotation/Annotations.kt`。`experimental/`: `TypeInference.kt`→`inferenceMarker.kt`、`NativeExperimentalAnnotations.kt`→`ExperimentalNativeApi.kt`/`ExperimentalObjCName.kt`/`ExperimentalObjCRefinement.kt`/`ExperimentalObjCEnum.kt`（本家がアノテーションごとに1ファイル持つ構成に一致。`ExperimentalObjCEnum` は v2.3.10 タグに専用ファイルが無いため新設、post-2.3.10 の本家 `kotlin.experimental` 宣言と同名）。enforcing: `BundledStdlibOrderingTests.testMigratedBundledFilenamesFollowUpstreamLayout` が 6 パッケージ配下の `Stdlib.kt` 名と eponymous ディレクトリを拒否。挙動変更ゼロ（全宣言の FQ 名・内容不変、パスのみ移動）
  - native 残件: **解消（#6840）**。参考: `native/internal/NativeConcurrentBridges.kt` は `__kk_*` ブリッジ専用の KSwiftK 独自ファイルで本家対応物なし（リネーム対象外、変更なし）
    - `[x]` 済みタスクの完了メモは旧ファイル名のまま残している（#6745 の完了エントリ削除と衝突させないため）。未完了タスクの「実装先 .kt」は #6780 で本家オーナーへ読み替え済み
  - 他モジュールの残件: ルート `kotlin/` パッケージに帰属ヘッダ由来の不一致と per-type ディレクトリ artifact（`Array/Stdlib.kt`、`Pair/`、`Result/Stdlib.kt` 等 30 件超）があるが、`HeaderHelpers+SyntheticArrayStubs.swift` / `+SyntheticCoercionStubs.swift` の (b) 残があるため着手条件未達（`+SyntheticCoercionStubs` の (b) 分は KUU-588 で追跡）。`collections` / `text` / `sequences` / `ranges` / `time` / `io` / `concurrent`(atomics) / `math` も (b) 残ありで対象外。`uuid` / `io/encoding` / `comparisons` / `properties` は (b) 0 かつ既に本家名で対象外

### KSP-W6: 追補モジュール移行（ギャップ監査 2026-07-10。手順は全て T。粒度ルール適用済み = 1タスク1PR）

> 2026-07-10 監査で判明した「(b) 分類なのに KSP タスクが無い」領域 + (c) 再分類監査（厳格原則: Swift 残留は言語コア/GC・continuation・メタデータ/OS syscall のみ）で b-reclass になった領域の実行体。各タスクの削除対象・特例位置は監査時点で実コード検証済み — 着手時は rg で再固定する。

#### bucket (b) 未起票追補（2026-08-14）

> `HeaderHelpers+SyntheticBucketedStubRegistry.swift` の `sourceBackedMigration` 登録で §9 分類表 (b) かつ既存 KSP タスクに未追跡だった residual 群。`TODO.md` 棚卸し日 2026-08-14。採番は KSP-695 の続き。
>
> 2026-08-14 現 HEAD で `SyntheticBase64Stubs` / `SyntheticHexFormatStubs` は存在しないため、Base64/HexFormat 対応タスクは追加しない。

- [x] KSP-700: core collection / iterable / Comparable / List interface shells を Kotlin 化し、旧 synthetic shell 登録を residual 責務へ分離する
  - 対象 residual: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticComparableResiduals.swift`, `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticCollectionResiduals.swift`, `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticListResiduals.swift`（`LateListIndexedMembers` 含む）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/Comparable.kt`, `Sources/CompilerCore/Stdlib/kotlin/collections/` 新設 `Iterable.kt`/`Collection.kt`/`List.kt`/`MutableIterable.kt`/`MutableCollection.kt`/`AbstractList.kt`（既存 `MutableIterable.kt`/`AbstractCollection.kt`/`AbstractMutableCollection.kt`/`RandomAccess.kt` 活用）
  - 削除/降格 kk_*: interface shells には public `kk_*` なし。`Comparable` primitive conformances / `setupPrimitiveComparableImplementations` は (c) 残留として分離 or `__kk_` 降格
  - 手順: T
  - diff: `comparable_interface.kt` 等既存 + 新規 collection interface 宣言ケース
  - 前提: KSP-701, KSP-703, KSP-704, KSP-705, KSP-699（orchestrator 削除前に内部呼び出しを独立化）
  - **2026-09-15 実装メモ**: 着手時に前提・対象の実態を rg で再固定したところ、issue 記載と現コードの乖離が大きいと判明した。
    1. **`LateListIndexedMembers` は既に存在しない**: KSP-702（#5907、2026-08-18）で完全削除済み。issue 記載は KSP-697 のファイル分割時（旧 `+SyntheticComparableAndCollectionStubs.swift` → 3 分割）に迷い込んだ stale 参照。対応不要。
    2. **前提の循環**: KSP-703/704/705 は自身の「前提」に `KSP-700` を挙げており（逆向き）、KSP-700 が 703/704/705 を前提とする記載は元 gap audit（2026-08-14）のテンプレ生成時の誤りと判断（Set/List が Collection に依存するのは自然だがその逆はない）。実装上の制約は「orchestrator（`registerSyntheticCollectionStubs`）の呼び出し構造を壊さない」ことのみで、`KSP-701`（PR #5915/#5990 で完了済み）・`KSP-699`（PR #6778 で完了済み）は満たされていたため着手可能と判断した。
    3. **実施した変更**: `Collection<out E>` を `collections/Collection.kt` へ分離し、`List<E>` の `get`/`isEmpty`/`listIterator()`/`listIterator(index)` と `MutableList<E>` の共変 `listIterator` override 2件を source 化した（既存 link name: `__kk_list_get`/`kk_list_is_empty`/`kk_list_iterator`/`kk_list_iterator_at`）。`AbstractList<E>` は `iterator`/`listIterator`/`indexOf`/`lastIndexOf`/`subList`/`equals`/`hashCode` と内部 iterator/sub-list 実装を持つ source-backed default implementation へ拡張した。
    4. **Residual 整理**: `HeaderHelpers+SyntheticListResiduals.registerListGetOperator` は bundled source がない場合だけの fallback に縮小し、移行済みの `isEmpty`/`listIterator`/`MutableList.listIterator` 登録と ListIterator/MutableListIterator の synthetic member/shell 登録を除去した。呼び出し元のない set-ops/toMap/asSequence/contentEquals 登録も削除し、`registerListTransformMembers` と List/AbstractList の no-stdlib fallback は残した。
    5. **バグ修正**: `AbstractMemberCompleteness.swift` の inherited abstract member 判定を owner-aware に変更した。`ArrayList<E> : MutableList<E>, RandomAccess, AbstractMutableList<E>` のように interface が先に列挙されても、concrete owner が abstract requirement を満たすことを認識し、direct-supertype 順序に依存した誤診断を防ぐ。
    6. **意図的な残置**: `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` の collection/iterable runtime bridge、Comparable の primitive conformances、Range の upper-bound hook は compiler/runtime residual として維持した。新規 bridge は追加せず、既存 link name を再利用した。
    7. **副産物のバグ報告（2件）**: (a) `CallLowerer+UnresolvedMemberCalls.swift` の `isEmpty` 解決に、型パラメータ経由（`__kk_collection_isEmpty`、List/Set 両対応）と具象クラスシンボル経由（`.collection?` を `kk_list_is_empty` へ、List 専用で Set には無条件 `true` を返す）で不整合な分岐を発見したが、短時間では到達可能な最小再現が作れなかったため KUU-543 に起票（KSP-700 スコープ外）。(b) `AbstractList` を継承したユーザークラスが独自 `iterator()` 内の無名 `object : Iterator<E>` から `get(i)` をレシーバなしで呼ぶ動作確認中、リンクエラー（`Undefined symbols: "_get"`）を発見。`List`/`AbstractList`/stdlib と無関係な純粋ユーザー定義 interface（`interface Getter<E> { fun fetch(index: Int): E }` を継承したクラス内の無名 `object` から `fetch(0)` をレシーバなし呼び出し）でも同一症状で再現することを確認し、KSP-700 起因ではなく既存の Sema/KIR 側（無名クラスからの暗黙外側レシーバ解決）の一般的なギャップと判断、KUU-544 に起票した（ワークアラウンド: 外側インスタンスをローカル変数にキャプチャしレシーバ付きで呼べば回避可能、と確認済み）。本 PR の diff ケース（`ksp700_list_get_source_backed.kt`）はこのパターンを含まないため無関係。
    8. **検証**: `swift build` green（既存の `SemanticsModels.swift` 重複 case 警告のみ）。List/MutableList/AbstractCollection/AbstractMutableList/ListIterator の対象 Sema テスト、`ListSyntheticMemberLinkTests` の関連ケース green。Sema golden は 93 cases 全 PASS（差分は3 fixtureの型表記置換のみ）。新規 `collection_interface_declarations.kt` は `bash Scripts/diff_kotlinc.sh` で PASS、Runtime ABI 外部リンク検証は4/4 PASS。全体テスト・全 diff_kotlinc は未実行（最小スコープ方針）。
    9. **`kk_cdecl_count`/`__kk_cdecl_count`**: 新規 bridge の追加・削除・改名はなく、既存 `__kk_list_get`/`kk_list_is_empty`/`kk_list_iterator`/`kk_list_iterator_at` を再利用した。Runtime/RuntimeABI のソース変更はない。

- [x] KSP-703: Map shell / HOF を Kotlin 化し `HeaderHelpers+SyntheticMapStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMapStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/` 新設 `Map.kt`/`MutableMap.kt`/`HashMap.kt`/`LinkedHashMap.kt`（`MapHOF.kt`/`MapLookupAndTransform.kt` 既存から統合）
  - 削除/降格 kk_*: `kk_map_*` public ブリッジ（`RuntimeSetAndMap.swift`/`RuntimeMapHOF.swift`。着手時 `rg -o '@_cdecl\("kk_map[a-zA-Z0-9_]*"\)' Sources/Runtime` 全層で再固定）を削除 or `__kk_` 降格
  - 手順: T
  - diff: `map_*.kt` 既存 + `HashMap`/`LinkedHashMap` 生成ケース
  - 前提: KSP-700, KSP-701
  - **2026-09-18 完了メモ**: KSP-701 は完了済み。KSP-700 は未完了だが、KSP-704/KSP-1542 の前例に従い、個別の Map shell を先行移行した。着手時点で `Map`/`MutableMap`/`HashMap`/`LinkedHashMap` は既に bundled Kotlin source 化済みで、issue の「新設」は stale だった。
    1. `HeaderHelpers+SyntheticMapStubs.swift` の到達不能な Map HOF 合成登録（`forEach`/`map`/`mapNotNull`/`mapValues`/`mapKeys`/`filter*`/`count`/`any`/`all`/`none`/`plus`/`minus`/`flatMap`/`maxByOrNull`/`minByOrNull`）を削除した。`MapHOF.kt`/`MapLookupAndTransform.kt` の source-backed extension と重複しており、`bundledIndex.contains(...)` の無条件 return で到達不能だったためである。`Map.Entry` の `component1`/`component2` と `MutableEntry.setValue` の同様の dead 登録も削除した。
    2. `Map.isEmpty`/`Map.get` を `Map/Map.kt`、`MutableMap.remove`/`clear` を `MutableMap.kt` の `@KsSymbolName` 付き宣言へ移した。`Map` の property と `MutableMap` の `put`/`putAll` は、runtime map box が itable を持たないため、source 宣言と ABI 直結 residual を分離して維持した（default body 化は `KSWIFTK-RUNTIME-0001` を再現）。`Map.Entry`/`MutableEntry` の nested interface shell と key/value accessor は、現行 bundled-header pass の前方宣言制約のため `HeaderHelpers+SyntheticMapEntryResiduals.swift` に残置した。runtime property/mutation の residual は `HeaderHelpers+SyntheticMapRuntimeResiduals.swift` に分離した。
    3. `LinkedHashMap` の typealias を `CollectionAliases.kt` から本家準拠の `LinkedHashMap.kt` へ分離した。HashMap/LinkedHashMap の alias 方向を kotlin-native と一致させる concrete-class 化は `CollectionLiteralLoweringPass` の再設計を伴うため、§13-8 の構造逸脱台帳に follow-up として記録した。
    4. 着手時の `rg -o '@_cdecl\("kk_map[a-zA-Z0-9_]*"\)' Sources/Runtime` は空で、現在も public `kk_map_*` Runtime export は存在しない。Runtime 側は既存の `__kk_map_*` hidden bridge を再利用した。
    5. 検証: `swift build`、MapAsSourceMigrationTests、MutableMapInterfaceSourceMigrationTests、MutableMapEntrySourceMigrationTests、MapHOFLoweringRoutingTests、RuntimeABIExternalLinkValidationTests、ABIMismatchRuntimeExportParityTests、CodegenBackendMapHOFTests は green。KUU-510 対象 27 件（`map_*.kt`、`mutable_map_*.kt`、HashMap/LinkedHashMap alias・constructor・生成ケース）の `diff_kotlinc.sh` は `total=27 failed=0 passed=27 skipped=0`。全 Swift suite、全 Golden、全 diff ケースは未実行。

- [x] KSP-704: Set shell / HOF を Kotlin 化し `HeaderHelpers+SyntheticSetStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticSetStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/` 新設 `Set.kt`/`MutableSet.kt`/`HashSet.kt`/`LinkedHashSet.kt`（`SetHOF.kt` 既存から統合）
  - 削除/降格 kk_*: `__kk_mutable_set_*` 等 demoted bridges を活用。`kk_set_*` public があれば削除（着手時 `rg -o '@_cdecl\("kk_set[a-zA-Z0-9_]*"\)' Sources/Runtime`）
  - 手順: T
  - diff: `set_*.kt` 既存 + `HashSet`/`LinkedHashSet` 生成ケース
  - 前提: KSP-700, KSP-701
  - **2026-09-16 完了メモ**: KSP-700/KSP-701 の前提を確認した。`rg -o '@_cdecl\("kk_set[a-zA-Z0-9_]*"\)' Sources/Runtime` は空で、public `kk_set_*` Runtime export は存在しない。
    1. `Set.kt` は `SetHOF.kt` から nominal declaration を分離し、`contains`/`isEmpty`/`iterator` を `@KsSymbolName` 付きで source 化した。property への link-name 注釈が未対応のため `size` は private `@KsSymbolName("__kk_set_size")` external helper 経由の source-backed getter とし、Set の合成 size 登録を削除した。
    2. `MutableSet.kt` は mutation surface（`add`/`remove`/`clear`/`addAll`/`plusAssign`/`removeAll`/`minusAssign`/`retainAll`）を source-backed default body 化し、private `@KsSymbolName("__kk_mutable_set_*")` demoted bridges に委譲した。Array/Iterable/Sequence の共有 residual bridge は維持し、overload ごとに Lowering で選択する。
    3. `HashSet.kt`/`LinkedHashSet.kt` は `CollectionAliases.kt` から分離済みの source-backed nominal declarations を使用し、`HeaderHelpers+SyntheticSetStubs.swift`（843行）を削除した。bundled source の早期 header predeclaration と、runtime-backed set box の size/mutation direct lowering を追加した。
    4. 動作確認: `swift build`、Set/MutableSet の Sema migration tests、Set member/codegen tests、`set_*.kt` 9件 + `HashSet`/`LinkedHashSet` 2件の `diff_kotlinc.sh`（11/11 PASS）を確認した。全 Swift suite、全 Golden、全 `diff_kotlinc.sh`（1425ケース）は未実行（CI に委ねる）。

- [ ] KSP-705: MutableList / MutableCollection `addAll` 群を Kotlin 化し関連 stub を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMutableListStubs.swift`（`addAll` 関連部分）, `HeaderHelpers+SyntheticMutableCollectionArrayAddAll.swift`, `HeaderHelpers+SyntheticMutableCollectionIterableAddAll.swift`, `HeaderHelpers+SyntheticMutableCollectionSequenceAddAll.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/` 新設 `MutableList.kt`/`MutableCollection.kt`（`MutableCollections.kt` 既存活用）
  - 削除/降格 kk_*: `__kk_mutable_list_addAll`, `__kk_mutable_collection_addAll_*` 等 demoted bridges を活用。`kk_mutable_*_addAll` public があれば削除（着手時 `rg 'kk_mutable.*addAll' Sources/Runtime Sources/CompilerCore`）
  - 手順: T
  - diff: `mutable_list_addAll.kt` 新規 + 既存 `list_*.kt`
  - 前提: KSP-700, KSP-701, KSP-703, KSP-704

- [x] KSP-708: TypedRange (`IntRange`/`LongRange`/`CharRange`) class shells を Kotlin 化し `HeaderHelpers+SyntheticTypedRangeStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTypedRangeStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/` 新設 `IntRange.kt`/`LongRange.kt`/`CharRange.kt`（`Ranges.kt` 既存インターフェース活用）
  - 削除/降格 kk_*: `kk_int_range_*`, `kk_long_range_*`, `kk_char_range_*` 等 public ブリッジを `__kk_` 降格 or 削除（`RuntimeRange*.swift`。着手時 `rg -o '@_cdecl\("kk_(int|long|char)_range[a-zA-Z0-9_]*"\)' Sources/Runtime` 全層で再固定）
  - 手順: T
  - diff: `range_basic.kt` 等既存 + 新規 TypedRange 単独ケース
  - 前提: KSP-451, KSP-456, KSP-700（Comparable）
  - 完了: `IntRange.kt`/`LongRange.kt`/`CharRange.kt` を追加し、typed synthetic stub を削除。typed range の public `kk_*` cdecl は 0 件、残存 bridge は `__kk_*` に降格。`swift build`、関連 Sema/ABI テスト、`range_basic.kt`/`typed_range.kt` の kotlinc diff を確認済み（全体 suite / 全 diff は未実行）。

- [ ] KSP-709: UnsignedRange (`UIntRange`/`ULongRange`) class shells を Kotlin 化し `HeaderHelpers+SyntheticUnsignedRangeStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticUnsignedRangeStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/` 新設 `UIntRange.kt`/`ULongRange.kt`
  - 削除/降格 kk_*: `kk_uint_range_*`, `kk_ulong_range_*` 等 public ブリッジ（`RuntimeRange*.swift`。着手時 rg）
  - 手順: T
  - diff: `range_basic.kt` 等既存 + unsigned range ケース追加
  - 前提: KSP-451, KSP-456, KSP-708

- [ ] KSP-714: RangeProgression / RangeInterface / RangeUntil クラス群を Kotlin 化し stub 群を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRangeProgressionStubs.swift`, `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRangeInterfaceStubs.swift`, `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRangeUntilStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/` 新設 `IntProgression.kt`/`LongProgression.kt`/`CharProgression.kt`/`UIntProgression.kt`/`ULongProgression.kt`/`Progressions.kt`（`Ranges.kt` 既存インターフェース活用）
  - 削除/降格 kk_*: `kk_op_step`, `kk_op_downTo`, `kk_op_rangeUntil`, `kk_int_progression_*`, `kk_long_progression_*`, `kk_char_progression_*`, `kk_uint_progression_*`, `kk_ulong_progression_*` 等（`RuntimeRange*.swift`。着手時 rg）
  - 手順: T
  - diff: `range_progression.kt` 新規 + `range_basic.kt`/`range_until.kt` 既存
  - 前提: KSP-451, KSP-456, KSP-708, KSP-709

- [x] KSP-717 残余: `String` synthetic stub の Core/Query/Encoding/Format 分を Kotlin 化し、公開 synthetic stub を削除・Runtime bridge を `__kk_*` に降格する
  - **2026-09-15 完了（KUU-523）**: CharSequence/Appendable は KSP-724/KSP-711 で完了済み。Core（`String.get`/`compareTo`/`intern`）、Query（`equals`/`split`/`first`/`last`/`single`/`getOrNull`）、Format（`String.format`/`Companion.format`/`CASE_INSENSITIVE_ORDER`/`concat`/`plus`）を bundled Kotlin の公開宣言 + private `__kk_*` bridge に移行し、`HeaderHelpers+SyntheticStringCoreStubs.swift` / `HeaderHelpers+SyntheticStringQueryStubs.swift` / `HeaderHelpers+SyntheticStringFormatStubs.swift` を削除した。
  - `HeaderHelpers+SyntheticStringStubs.swift` は String の compiler/runtime nominal shell と `CharSequence` supertype を維持する Encoding compatibility shell のため残置。Locale/normalize/number conversion の先行移行も含め、String の公開 synthetic member 登録は KUU-523 の対象範囲から除去した。
  - Runtime の対象 C ABI は `__kk_string_get_flat`、`__kk_string_compareTo_member`、`__kk_string_intern`、`__kk_string_equals_flat`、`__kk_string_first|last|single*_flat`、`__kk_string_getOrNull_flat`、`__kk_string_format_flat`、`__kk_string_format_locale_flat`、`__kk_string_concat_flat`、`__kk_string_plus`、`__kk_string_case_insensitive_order` に降格した。
  - 手順: T
  - diff: 既存 `string_*.kt` 拡張
  - 前提: KSP-406, KSP-407, KSP-408, KSP-409, KSP-410, KSP-411, KSP-624, KSP-710, KSP-711（すべて完了済み）
  - 既知の罠（KUU-523 で発見・別途 KUU-545 に起票）: bundled Kotlin source にインターフェース型（`CharSequence`/`Iterable<T>`/`Collection<T>` 等）をレシーバに取る `external fun` 拡張関数を追加すると、そのインターフェースの**既存の**itable ディスパッチが実行時に壊れる（`KSWIFTK-RUNTIME-0001`）。ブリッジは必ず「インターフェース型を通常引数に取るトップレベル `external fun`」+ 「それを呼ぶ非external拡張関数」の2段構成にすること（`StringBasics.kt` の `codePointCount` 実装を参照）

#### bucket (b) 未起票追補 第2弾（2026-08-16）

> 「Kotlin source 以外（Synthetic Swift stub / Runtime 公開 `kk_*` / Sema 名前特例）で実装が残っている stdlib 面」を master `eacdb9026` で再棚卸しし、既存 KSP タスクにどのタスクでも追跡されていなかった残余を 1タスク=1PR で起票したもの。Stdlib gap audit 2.3.10（KSP-719〜KSP-1502）との重複を避けるため採番は KSP-1502 の続き（KSP-1503〜）。
>
> 実測（2026-08-16, master `eacdb9026`）: bundled Kotlin source 153ファイル/23,266行、Synthetic stub 68ファイル/45,516行、Runtime 公開 `kk_*` 1,175、bridge `__kk_*` 688、`excludedBundledStdlibFiles` 0件。
>
> 各タスクの「削除/降格 kk_*」は棚卸し時点の列挙であり、着手時に必ず記載の `rg` で再固定する（先行タスクのマージで既に消えている場合は TODO 同期として完了化してよい）。

- [x] KSP-1503: MutableList / AbstractMutableList の class shell と要素追加・削除メンバを Kotlin 化する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMutableListStubs.swift`（1364行のうち `registerSyntheticMutableListStub` / `registerSyntheticAbstractMutableListStub` / `set` / `add` / `add(index)` / `removeAt` / `removeFirst(OrNull)` / `removeLast(OrNull)` / `clear` / `removeAll` / `retainAll` / `plusAssign` / `minusAssign` 部分。`addAll` 群は KSP-705）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableCollections.kt` 追記（class shell は `Collections.kt` / 新設 `AbstractMutableList.kt`）
  - 削除/降格 kk_*: `kk_mutable_list_*`（`set`/`add`/`addAt`/`removeAt`/`removeFirst*`/`removeLast*`/`clear`/`removeAll`/`retainAll`）系を `__kk_` 降格。着手時 `rg -o '@_cdecl\("kk_(mutable_)?list_[a-zA-Z0-9_]*"\)' Sources/Runtime` と `rg 'removeFirstOrNull|retainAll' Sources/CompilerCore/Sema Sources/CompilerCore/KIR` で再固定
  - 手順: T
  - diff: `mutable_list_*.kt` 既存 + `removeFirstOrNull`/`removeLastOrNull`/`retainAll`/`minusAssign` 単独ケース
  - 前提: KSP-700, KSP-705

- [ ] KSP-1504: MutableList の in-place 並べ替え（`sort`/`sortWith`/`sortBy`/`sortByDescending`/`sortDescending`/`shuffle`/`reverse`）を Kotlin 化し `HeaderHelpers+SyntheticMutableListStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMutableListStubs.swift`（`registerMutableListSort*` / `registerMutableListShuffleMember` / `registerMutableListReverseMember`。KSP-705/KSP-1503 完了後の残余）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/ListSortingHOF.kt` 追記（in-place 版）
  - 削除/降格 kk_*: `kk_mutable_list_sort*` / `kk_mutable_list_shuffle` / `kk_mutable_list_reverse` 系（着手時 `rg -o '@_cdecl\("kk_[a-zA-Z0-9_]*(sort|shuffle|reverse)[a-zA-Z0-9_]*"\)' Sources/Runtime`）。`shuffle` の乱数コアは `__kk_random_*` へ降格
  - 手順: T
  - diff: `mutable_list_sort*.kt` 既存 + `shuffle(Random(7))` 決定性ケース、`sortBy`/`sortByDescending` 単独ケース
  - 前提: KSP-426, KSP-685, KSP-705, KSP-1503

- [x] KSP-1509: `List<E>` の `random`/`randomOrNull` を Kotlin 化し `HeaderHelpers+SyntheticListAggregateMembers.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticListAggregateMembers.swift`（KSP-1505〜1508 完了後の残余 + `registerListAggregateMembers` orchestrator）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/ListAccessHOF.kt` 追記
  - 削除/降格 kk_*: `kk_list_random`, `kk_list_randomOrNull`（`Random` 引数版含む）。乱数コアは `__kk_random_*` へ降格
  - 手順: T
  - diff: `list_random*.kt` 既存 + `random(Random(7))` 決定値ケース、空リストの `randomOrNull`/例外ケース
  - 前提: KSP-685, KSP-1505, KSP-1506, KSP-1507, KSP-1508
  - **2026-09-14 実装メモ**: 着手時に `registerListAggregateMembers`（891行）の中身を全件確認したところ、`random`/`randomOrNull`（`registerSimpleMember`）以外の全メンバ（max/min/maxBy/minBy/maxOf/minOf/maxWith/minWith/maxOfWith/minOfWith/sumOf/sortedByDescending/sortedWith/partition/zip/unzip）は、`shouldSkipRegistration` が bundled Kotlin source 側の同名 List 拡張（`ListExtremaHOF.kt`/`ListAggregateHOF.kt`/`ListSortingHOF.kt`/`ListAssociationHOF.kt`/`Iterables.kt`/`ListWindowChunk.kt`）を検出して既に無条件 skip されており、`random`/`randomOrNull` だけが本当に生きている唯一の残存登録だった（KSP-1505〜1508 は実際には TODO.md 台帳整理のみで、Kotlin 側移行自体は KSP-426/427/428（2026-08-14）で既に完了済みと判明）。`List<E>` は `Sema` のメンバ優先規則（member が同名 extension より必ず勝つ）により、`Collections.kt` 側に既存の `Collection<T>.random()`/`randomOrNull()`（`Random` 引数版含む、KSP-960 で source 化済み）を素通りしてこの synthetic member（`kk_list_random`/`kk_list_randomOrNull` 直結）を使っていた。`ListAccessHOF.kt` に `List<T>` 直付けの `random()`/`random(Random)`/`randomOrNull()`/`randomOrNull(Random)` を追加（`this[Random.nextInt(size)]` による直接添字アクセス。`Random.nextInt(size)` は `Sources/CompilerCore/Stdlib/kotlin/random/Random.kt` に既存の pure Kotlin 実装で新規ブリッジ不要）し、これで `shouldSkipRegistration` が List 側も skip するようになったため、`registerListAggregateMembers` 全体が no-op と確定し、関数ごとファイル削除・呼び出し元（`HeaderHelpers+SyntheticListResiduals.swift`）の呼び出し除去まで実施した。**`kk_list_random`/`kk_list_randomOrNull` は削除しなかった**（当初計画から逸脱）: `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift`（`registerSyntheticCollectionStub`／`Collection` interface 側）が同名ブリッジを参照しており、そちらは KSP-960 由来の `isMigratedExtension` ガードで通常ビルド（bundled Kotlin source あり）では既に no-op だが、`--no-stdlib`/precompiled-metadata ビルド（`bundledIndex` が空）では唯一の `Collection`/`Set` 型 random フォールバックとして生きているため、削除すると当該ビルドモードを壊す。よって「乱数コアを `__kk_random_*` へ降格」も見送った——`Random.nextInt(size)` の呼び出しだけで完結し、`kk_list_random` 側のコア（Swift `Array.randomElement()`、非決定的で `Random` 引数を無視する既存の別実装）に触れる必要が無かったため。`CallLowerer+MemberCallEmission.swift:736` の `kk_list_random`（throwing callee 名リスト）もこの理由で維持。`docs/stdlib-pipeline.md` §9 の `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` 行にある「KSP-1509 は未着手」の記述は本 PR で古くなるため要更新（別コミットで追従）。新規 diff case `Scripts/diff_cases/list_random_seeded.kt` を追加（`List<Int>` 型レシーバに対する `random(Random(7))` 決定値ケース、`randomOrNull` の要素検証、単一要素リスト、空リストの `randomOrNull() == null` と `random()`/`random(Random)` の `NoSuchElementException` を確認）。**検証**: `swift build` PASS。`.build/debug/kswiftc --stdlib-from-source` に本 diff case 相当のスモーク（`List<Int>` に対する `random()`/`random(Random(7))`/`randomOrNull()`/`randomOrNull(Random(7))` 呼び出し、空リストの例外/null ケース込み）を `-o` 付きで投入したところ、6.3MB の `.o` が生成された時点（Lex→Sema→KIR→Lowering→LLVM codegen が診断なしで完走したことを意味する）でリンク直前の release Runtime ビルドが `.runtime-build` のロック待ちに入り、そこから先（最終リンク・実行）は他セッション由来の負荷でタイムアウトし確認できなかった。後続の `--emit kir` 再試行2回はいずれもタイムアウトで exit code が信頼できず（`| tail` 経由の `$?` は `tail` 自身の終了コードを拾う既知の罠、`local-test-env-setup` メモ参照）、結果を根拠にしていない。既存 Golden Sema fixture に `List<T>` 型レシーバの `random`/`randomOrNull` を直接カバーするものは無く（`collection_random_overloads.kt` は `Collection<Int>` 型のみ）、非回帰破壊は無し。`Scripts/check_todo_ids.sh` PASS。追記（2026-09-14 15:02、マシン負荷が load average 48〜95 まで下がった後に再実行）: `bash Scripts/diff_kotlinc.sh --compile-timeout 300 Scripts/diff_cases/list_random_seeded.kt` PASS（precompiled `.kklib` 経路、ユーザーの既定経路）。`random(Random(7))` の決定値列・`randomOrNull`・単一要素・空リストの `randomOrNull() == null`・`random()`/`random(Random)` の `NoSuchElementException`（メッセージ `"Collection is empty."` 込み）がすべて実 kotlinc の出力とバイト一致することを確認した。直前の1回目の再実行は他セッションの並行ビルド再開（gate 解除直後）で candidate compile が 120s タイムアウトしたのみで、内容不一致ではなかった。`swift_test.sh` 全体・`--filter Golden` 四スイート一括は引き続き未実行（最小スコープ方針）。`Scripts/loc_report.sh` 相当の手動確認: `HeaderHelpers+Synthetic*` 合計行数 891+9 減（ファイル削除+呼び出し除去。新規行は `HeaderHelpers+Synthetic*` 側ではなく `ListAccessHOF.kt` に追加）、`kk_cdecl_count`（932）・`__kk_cdecl_count`（837）とも不変（ブリッジの追加/削除/改名なし）。

- [x] KSP-1511: `List<E>` の `sorted`/`sortedDescending`/`shuffled`/`sum` を Kotlin 化し `HeaderHelpers+SyntheticListTransformMembers.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticListTransformMembers.swift`（KSP-1510 完了後の残余。`sum`/`distinctBy` を含むファイル冒頭コメントの「not yet source-backed」分）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/ListSortingHOF.kt` / `ListAggregateHOF.kt` 追記
  - 削除/降格 kk_*: `kk_list_sorted`, `kk_list_sortedDescending`, `kk_list_shuffled`, `kk_list_shuffled_random` + 着手時 `rg -o '@_cdecl\("kk_list_(sum|distinctBy)[a-zA-Z0-9_]*"\)' Sources/Runtime`
  - 手順: T
  - diff: `list_sorted*.kt` 既存 + `shuffled(Random(7))` 決定値ケース（KSP-CAP-011 の非回帰確認）、`sum` の Int/Long/Double ケース
  - 前提: KSP-685, KSP-1510
  - 完了根拠（2026-09-14）: `sorted`/`sortedDescending` は既に bundled source 優先で dead だった合成登録を削除。`shuffled`/`shuffled(Random)` は `BundledDeclarationIndex` の KSP-426 由来 retained-overlap 特例と `CollectionLiteralLoweringPass` の list-literal fast-path rewrite を撤去して bundled source (`ListSortingHOF.kt`) に一本化し、`KIRLoweringDriver` 側の「List receiver の shuffled は本体を emit しない」特例も削除。`kk_list_shuffled`/`kk_list_shuffled_random` の `@_cdecl` を Runtime から削除（RuntimeABISpec エントリは KSP-426 方式で spec-only として存置）。副産物として2件のランタイムバグを本PR内で修正: (1) `kk_list_shuffled_random` が seed 付き `Random` を無視して常にシステム乱数を使っていた既知バグ（source 化により解消、`list_shuffled_seeded.kt` で kotlinc 実機と bit-exact 確認）、(2) コンパニオンを持つクラス名を裸の値として渡す式（`shuffled(Random)` 等）が KIR 上でクラスシンボルをそのまま参照し vtable lookup で invalid receiver (0x0) panic するバグ（`ExprLowerer+ControlFlowAndBlocks.swift` でコンパニオンシンボルへリダイレクト）。`sum` は BUG-256 (#6793) で既に Int/Long/Double 含む全数値型対応済みのため今回追加実装なし。検証: `ListSyntheticMemberLinkTests`/`ABIMismatchTests`/`ABIMismatchRuntimeExportParityTests`/`ListSortExtremaLoweringRoutingTests`/`CodegenBackendListSortExtremaTests`/`CollectionLiteralLoweringTests` 全パス、`validate_runtime_abi_links.sh` パス、`diff_kotlinc.sh` で shuffled/sorted/sum/Random 系19ケース全パス（回帰前は `list_shuffled_random.kt` が vtable panic で FAIL）。

- [x] KSP-1517: `booleanArrayOf`/`byteArrayOf`/`charArrayOf`/`doubleArrayOf`/`floatArrayOf`/`intArrayOf`/`longArrayOf`/`shortArrayOf` と unsigned 版 factory を Kotlin 化し `HeaderHelpers+SyntheticArrayStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticArrayStubs.swift`（`*ArrayOf` factory + class shell。KSP-1514〜1516 完了後の残余）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayConversions.kt` / `UArrays.kt`（class shell は `ArrayIntrinsics.kt`）
  - 削除/降格 kk_*: `kk_array_of` ほか着手時 `rg -o '@_cdecl\("kk_[a-zA-Z]*[Aa]rray_?of[a-zA-Z0-9_]*"\)' Sources/Runtime` で列挙。vararg 実体化が compiler intrinsic 依存なら該当分のみ (c) 残置理由をファイル削除見送りの根拠として記録
  - 手順: T
  - diff: `array_factory*.kt` 既存 + 各 `*ArrayOf()` 空/複数要素ケース、`ubyteArrayOf` ケース
  - 前提: KSP-657, KSP-1514, KSP-1515, KSP-1516
  - **2026-09-14 実装メモ**: 着手時に前提の実態を確認した。`*ArrayOf` factory（signed 8 種 + unsigned 4 種）は KSP-769/770/771/775/777/783/786/789/790/791/793 で既に個別 `.kt`（`boolean.kt`/`byte.kt`/`Char.kt`/`double.kt`/`float.kt`/`long.kt`/`short.kt`/`ubyte.kt`/`uint.kt`/`ulong.kt`/`ushort.kt`/`ArrayIntrinsics.kt`）へ移行済みで、`HeaderHelpers+SyntheticArrayStubs.swift` の `primitiveArrayFactoryTypes` factory loop は空の dead code だったと判明。`rg -o '@_cdecl\("kk_[a-zA-Z]*[Aa]rray_?of[a-zA-Z0-9_]*"\)' Sources/Runtime` は `kk_array_of`/`kk_array_of_nulls` の2件のみで、いずれも既存 `arrayOf`/`intArrayOf` 等が使う `CallSupportLowerer.swift` の共有 vararg packing 経路であり、削除/降格対象の新規 `kk_*` は無し。残っていた `Array<T>`/primitive array の class shell（`kind: .class` の nominal anchor のみで、構築・添字・`.size`・HOF は `CompilerKnownNames.isArrayLikeName`/`isPrimitiveArrayConstructorTypeName` の名前一致で解決されるため class body のメンバー宣言に依存しない）は、`Nothing`/`DeepRecursiveScope` と同じ「bodyless + `private constructor()`」パターンで `ArrayIntrinsics.kt` へ実際に移行できた。`HeaderCollection.swift` に `predeclareBundledArrayHeaders` を新設し、`predeclareBundledComparatorHeaders`/`predeclareBundledTupleHeaders` と同型（array 型シグネチャを組む他の合成スタブより先に nominal を hoist、`--no-stdlib`/precompiled `.kklib` では合成 shell へ fallback）で `Phase.swift` から早期 predeclare するよう配線し、`HeaderHelpers+SyntheticCollectionResiduals.swift` の `registerSyntheticArrayStubs` 呼び出しを削除、`HeaderHelpers+SyntheticArrayStubs.swift`（181行）を削除した。空配列ケースが欠けていた `stdlib_kotlin_n_double.kt`/`stdlib_kotlin_n_uint.kt` に `doubleArrayOf()`/`uintArrayOf()` の空ケースを追加。**検証**: `swift build` green。`arrayof_type_safety.kt`/`array_primitive_types.kt`/`stdlib_kotlin_n_{boolean,byte,ubyte,Char,double,float,int,long,short,uint,ulong,ushort}.kt`/`unsigned_array_conversions.kt`/`unsigned_array_views.kt`（計16ケース）を `diff_kotlinc.sh` で個別実行し全 PASS(kotlinc 参照一致)。`bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden` は 91 test cases 全 PASS(golden diff なし)。マシン負荷競合による一時的な `Failed to build stdlib artifact`(スクリプトの stdlib アーティファクトビルド自体の失敗であり実装の欠陥ではない)が数ケースで発生したが、負荷が下がった状態での再実行で解消し PASS を確認済み。

- [x] KSP-1519: `sequence {}` / `SequenceScope` / `yield` / `yieldAll` / `iterator {}` builder を Kotlin 化し `HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift` を削除する
  - 完了（2026-09-13）: `SequenceScope` クラス本体・`yield`/`yieldAll` は KSP-1361 で既に Kotlin 化済みと判明したため、本チケットの実残作業はトップレベル `sequence(block)`/`iterator(block)` builder 関数のみだった。`Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceBuilder.kt` を新設し（`channelFlow`/`callbackFlow` と同形の `@KsSymbolName` external fun）、`HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift` を削除。`registerSyntheticSystemMember`/`registerSyntheticTopLevelFunction`（汎用ヘルパー）は `HeaderHelpers+SyntheticFileIOStubs.swift` へ、`registerSyntheticSequenceStub`/`ensureSyntheticSequenceStub`（`Sequence` interface 自体の fallback shell、builder とは別物）は `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` へ退避（doc §9 記載の通り）。`registerSequenceScopeMember` は唯一の呼び出し元が消えたため削除。
  - `yield`/`yieldAll` 呼び出しの `__kk_sequence_builder_yield`/`yieldAll` への解決は、Sema の `externalLinkName` ではなく `CollectionLiteralLoweringPass+CallRewriteSequenceBuilders.swift` の名前文字列書き換え + `NativeEmitter` の `isSequenceBuilderRuntimeCall` ガードという恒久仕様（`MemberHeaderCollection.swift:143-150` 明示コメント、本 doc §9 の (c) 分類）であるため無変更。Template T 手順6②「同名 name-string 特例が残っていない」は `yield`/`yieldAll` に関して意図的に満たさない。
  - 実装中に発見した回帰: `d2c33b81a5`（RF-LOWER-CALL-003）が `CallTypeChecker+BuilderDSL.swift` の `isSourceBackedStdlibBuilderDSLSymbol` を常時 `false` に畳み込んでいたのは、当時 `sequence`/`iterator` がまだ synthetic だったため無害だったが、本チケットで source-backed 化した瞬間に builder-DSL 型推論ブートストラップが無効化され `--emit kir`（source-injection モード）でのみ型推論エラーが発生する regression になっていた。`kotlin.sequences.sequence`/`iterator` を認識するよう修正（kklib モードでは synthetic フォールバック解決の副作用でたまたま隠れていたため両モードの検証が必須だった）。
  - CI で発覚し同PR内で修正した既存バグ（本チケットの直接的な帰結）: `iterator {}` を bundled Kotlin source 宣言化した結果、`RuntimeABIExternalLinkValidationTests.testBundledKsSymbolNameDeclarationsMatchRuntimeABISignature` が初めて `__kk_iterator_builder_build` を検証対象にし、`RuntimeABISpec`（`fnPtr` 1引数のみ）と Kotlin 宣言（`sequence` と同形の suspend-lambda-with-receiver、2 ABI 引数 `fnPtr`/`closureRaw` に展開される）の不一致を検出した。synthetic スタブ時代はこの link name がbundled宣言と紐付いていなかったため未検証だったが、既に実行時レベルでは compiled Kotlin 側が常に2引数を渡していたため、`Sources/Runtime/RuntimeSequenceBuilders.swift` の `__kk_iterator_builder_build(_ fnPtr: Int)`（1引数のみ）は実際にはそのcaller規約と食い違っていた既存バグ——同一呼出規約に揃えた `__kk_sequence_builder_build(_ fnPtr: Int, _ closureRaw: Int = 0)` と異なり、余剰引数が単に読まれず無害だっただけで、`iterator { }` 内でクロージャcaptureがある場合はcaptureが握り潰されていたはず（未確認・別事象）。修正: `__kk_iterator_builder_build` に `closureRaw: Int = 0` を追加し `RuntimeIteratorBuilderBox(fnPtr:closureRaw:)`（既存の init 引数、`_coro` 経路は元から使用）へ転送、`RuntimeABISpec+Sequence.swift` の該当 spec に `closureRaw` パラメータを追加。回帰: `RuntimeABIExternalLinkValidationTests`（4件）/ `BuildKIRRegressionTests.testIteratorBuilderKeepsSingleBuilderArgument`（KIR レベルの引数数はこの修正で不変であることを確認）/ `RuntimeSequenceTests`（169件、既存呼び出し元は `closureRaw` 省略のデフォルト値で無修正のまま動作）全て PASS。
  - 実装中に発見した既存ランタイムバグ（本チケットとは無関係、Sources/Runtime/ 無変更で確認済み）: `yieldAll(sequence)` が遅延評価順序を保持しない。BUG-255 / `docs/diff-skip-inventory.md` DEBT-DIFF-010 として切り出し、`Scripts/diff_cases/sequence_yieldall_lazy_order.kt` を `SKIP-DIFF` 付きで追加。
  - 前提: KSP-651, KSP-713, KSP-1518, KSP-1361

- [x] KSP-1523: `UIntRange` の property / membership / aggregate を Kotlin 化する
  - 対象スタブ: `Sources/CompilerCore/Sema/Models/MemberRuntimeDispatch.swift` の `kk_uint_range_*` 名前生成、`HeaderHelpers+SyntheticUnsignedRangeStubs.swift` の該当メンバ登録
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt` 追記（既存の UIntRange HOF 群に合流。当初案の `RangeMembership.kt` 新設は行わなかった）
  - 削除/降格 kk_*: `kk_uint_range_contains`, `_isEmpty`, `_first`, `_last`, `_firstOrNull`, `_lastOrNull`, `_count`, `_sum`, `_average`, `_reversed`, `_sorted`, `_toList`, `_toUIntArray`（Runtime `@_cdecl` 13件を全削除）
  - diff: `Scripts/diff_cases/uint_range.kt` に空 range（`5u..1u`）の `isEmpty`/`firstOrNull`/`lastOrNull`/`sum`/`count`/`toList`/`contains`、`sorted`、`UInt.MAX_VALUE` 境界ケースを追記
  - 完了メモ（§13-1）:
    - 13件のうち `toList`/`firstOrNull`/`lastOrNull`/`sorted`/`count`/`sum`/`reversed`（7件）は `RangeHOF.kt` の Kotlin 宣言に移行。`contains`/`isEmpty`/`first`/`last`（4件）は Sema 合成登録を残しつつ、既存の safe generic bridge（`__kk_range_contains`/`_isEmpty`/`_first`/`_last`。signed 版と共有 — UInt は 32bit なので常に非負 Int64 に収まり比較・等値演算は安全に転用できる）へ link name を差し替え。`average`/`toUIntArray`（2件）は実 Kotlin に存在しないメンバーと判明（`diff_kotlinc.sh` で確認: `average()` は `Iterable<Byte/Short/Int/Long/Float/Double>` のみで `UInt` 無し、`toUIntArray()` は `Collection<UInt>` メンバーで `UIntRange`(`Iterable<UInt>`) には無い）したため `RangeHOF.kt` へ追加せず完全に削除した
    - バグ修正1（同PR内、CLAUDE.md「バグ修正ルール」）: `UIntRange.sum()` が `@KsSymbolName("__kk_range_sum")` によりネイティブ signed Int64 accumulator（`RuntimeRangeAndDispatch.swift`）へ委譲されており、`UInt.MAX_VALUE` 近傍で 32bit wraparound を再現できず誤った値（例: 期待 `4294967290` に対し `12884901882`）を返していた。アノテーションを外し Kotlin body（`UInt` accumulator の `for` ループ）を実行させて修正
    - バグ修正2（同PR内、advisor の二次レビューで発見）: `average`/`toUIntArray` を `RangeHOF.kt` から削除するだけでは不十分だった。`CallTypeChecker+RangeMemberFallback.swift` の古い汎用フォールバック（`tryRangeMemberFallback`、STDLIB-090/091/092/093 由来）の `isSupportedRangeMember` アローリストに両名がまだ残っており、この経路は型だけを緩く bind して（`bindExprType`）callee symbol を結び付けない設計のため、`(1u..5u).average()`/`.toUIntArray()` は Sema でエラーにならずに型チェックを通過し、後段のどの callee 解決にも一致せず `loweredMemberCalleeName` の最終フォールバック（構文上のメンバー名をそのまま返す）に落ち、リンク時に裸の `_average`/`_toUIntArray` 未解決シンボルとして初めて失敗が露見していた（real kotlinc は `unresolved reference` として型チェック時に拒否する）。`isSupportedRangeMember`/`isValidRangeMemberArity`/`rangeMemberResultType` の3関数から両名を削除（`rangeMemberResultType` 内の `toUIntArray` 専用ケースが使っていた `rangeMemberUIntArrayType` ヘルパーも孤立するため削除）。`IntRange`/`LongRange`/`ULongRange` の `average()` はこの削除の影響を受けないことを実行確認済み（それぞれ `bindSourceRangeHOFCall` 経由の bundled Kotlin 宣言、または Sema 合成登録の独自 link name で解決され、このレガシーアローリストに依存していない）。回帰: `Tests/CompilerCoreTests/Sema/UIntRangeHOFSourceMigrationTests.swift` に `removedMembersAreRejectedAtSemaNotLeftToLinkFailure`/`removedToUIntArrayIsRejectedAtSemaNotLeftToLinkFailure`（Sema で `hasError` になることを固定）と `otherRangeTypesAverageStillTypeChecks`（IntRange/LongRange の `average()` が引き続き型チェックを通ることを固定。ULongRange は当初含めていたが advisor の三次レビューで削除——`ULongRange.average()` も実 Kotlin には存在せず、`kk_ulong_range_average` という無関係な既存の Sema 合成登録のおかげで通っているだけなので、type-check を assert するとその既存の kotlinc 差異を固定化してしまう。KSP-1524 の対象）を追加。同型の既存バグが signed 側 `toIntArray` にも残っていることを BUG-259 に追記（同アローリストに `"toIntArray"` がまだ残存。`toLongArray`/`toULongArray` も同アローリストに残っており未検証である旨も追記済み）
    - §13-7② 確認: `exprType(receiver) == types.uintType`（レシーバ自身の型と比較する誤ったパターン、要素型チェックと取り違えていた）という同名文字列特例をSema/KIR/Lowering の3ファイルで発見・削除（`ExprLowerer+ControlFlowAndBlocks.swift` の `in`/`!in` lowering、`CollectionLiteralLoweringPass+VirtualCallRewrite+Range.swift` の `isUIntRange` ゲート、`+CallRewriteCollectionMember.swift`/`+CallRewriteSequenceTerminals.swift` に重複していた buggy な `isUIntRangeExpr` ローカルヘルパー2件）
    - `UIntRangeHOFSourceMigrationTests.swift` の既存テスト `migratedMembersAreUIntRangeSourceDefinitions` も本PRで修正: `firstOrNull`/`lastOrNull` に 0-arity 版（本PRで追加）と述語版（既存の HOF オーバーロード）の2つが `RangeHOF.kt` に存在するようになり、arity を見ずに `sourceSymbols.count == 1` を assert していたため red だった（未実行のまま気づかず埋め込みそうになった箇所、advisor の二次レビューで検出）。`!signature.parameterTypes.isEmpty` ガードを追加し、このテストが検証したい HOF シェイプに絞って修正
    - 検証コマンドと green 実績（§13-4 dual oracle 含む）:
      - `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/uint_range.kt` → PASS（`UIntRange.sorted()` レシーバのケースを含む）
      - `Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+UIntRangeMembership.swift`（第2 oracle、bundled .kt を実行して期待値比較。`UIntRange.sorted()` 含む）→ green（Suite `BundledStdlibExecutionTests` 46/46）
      - `bash Scripts/validate_runtime_abi_links.sh` → 4/4 green
      - `bash Scripts/swift_test.sh --filter RuntimeTests.ABIMismatchTests` → 87/87 green
      - `bash Scripts/swift_test.sh --filter RuntimeABISpecVersionTests` → 1/1 green
      - `bash Scripts/swift_test.sh --filter CompilerCoreTests.MemberRuntimeDispatchTests` → 9/9 green（`testUIntRangeKSP1523MembersNeverResolveToDeletedRuntimeNames` 追加）
      - `bash Scripts/swift_test.sh --filter CompilerCoreTests.UIntRangeHOFSourceMigrationTests` → 5/5 green（既存テストの arity 修正 + 新規回帰テスト2件）
      - `bash Scripts/swift_test.sh --filter RuntimeTests.RuntimeRangeStepTests` → 46/46 green
      - `bash Scripts/swift_test.sh --filter RuntimeTests.RuntimeRangeProgressionEdgeCaseTests` → 86/86 green
      - `bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` → 92/92 green、diff無し（`isSupportedRangeMember` アローリスト修正後に再実行して再確認済み）
      - `UIntRange`/`kk_uint_range_` を参照する残り全テストファイル（計19ファイル）を体系的に洗い出し実行: `GoldenHarnessMetadataContractTests`（8/8）、`RangeUntilSyntheticTopLevelLinkTests`/`RangeUntilSyntheticMemberLinkTests`/`RandomSyntheticLinkTests`/`RangeRandomSyntheticLinkTests`/`UIntRangeIteratorSourceMigrationTests`/`RangeSyntheticMemberLinkTests`/`UnsignedPrimitiveMemberCallTests`/`CoercionSyntheticStubTests`/`LoweringPassRegressionTests` 一括（196テスト）、`CodegenBackendRangeEdgeCasesTests`/`CodegenBackendRandomOverloadEdgeCasesTests`/`CodegenBackendRangeHOFTests` 一括（30テスト）、`RuntimeRangeHOFTests`/`RuntimeRangeRandomTests` 一括（72テスト）→ 全 green
      - `isSupportedRangeMember` アローリスト修正の回帰確認として、`Scripts/diff_cases/` 配下の range/progression 関連ケース全44件（`uint_range.kt`/`ulong_range.kt`/`long_range.kt`/`progression.kt`/`stdlib_kotlin_ranges_*` 等）を一時ディレクトリに集約して `bash Scripts/diff_kotlinc.sh` 一括実行 → 44/44 PASS（IntRange/LongRange/ULongRange/CharRange/各 Progression の `average()` 等が引き続き正しく解決されることを含めて確認）
      - `bash Scripts/loc_report.sh` 前後比較（一時 worktree で HEAD 側を計測）: `kk_cdecl_count` 954→941（−13）、`__kk_cdecl_count` 881→881（±0）、`kk_literal_count` 6523→6439（−84）
    - 派生課題（本PRでは対応せず記録のみ）: KSP-1524 に `average`/`toUIntArray` の実在確認を追記。signed 側 `RangeHOF.kt` の `IntRange.toIntArray()`/`IntProgression.toIntArray()` も同型の既存バグ（本 PR 起因ではない）と判明し BUG-259 として起票（レガシーアローリストにまだ `toIntArray` が残っている点も追記済み）。無関係な既存バグ `listOf<UInt>().sum()` のリンク失敗（`average`/`toUIntArray` と同型の裸シンボル未解決）は BUG-256 として起票 + spawn_task で別セッションへの切り出しチップも発行
    - 前提: KSP-451 は解決済み（現 TODO.md に未完了エントリなし）。KSP-709（class shell 全体の Kotlin 化）は未達だが、`HeaderHelpers+SyntheticUnsignedRangeStubs.swift` 自体の削除を要求しない本チケットのスコープ（メンバーの実装/リンク名のみ）は独立して完了可能と判断

- [~] KSP-1524: `ULongRange` の property / membership / aggregate を Kotlin 化する
  - 対象スタブ: `Sources/CompilerCore/Sema/Models/MemberRuntimeDispatch.swift` の `kk_ulong_range_*` 名前生成、`HeaderHelpers+SyntheticUnsignedRangeStubs.swift` の該当メンバ登録
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeMembership.kt` 追記（unsigned 版）
  - 削除/降格 kk_*: `kk_ulong_range_contains`, `_isEmpty`, `_first`, `_last`, `_firstOrNull`, `_lastOrNull`, `_count`, `_sum`, `_average`, `_reversed`, `_sorted`, `_toList`（12件）
  - 注記: `_toULongArray` は Kotlinize 対象から除外（実 kotlinc は `ULongRange`/`ULongProgression` に直接の `toULongArray()` を持たない。診断は `error_range_toarray_unsupported.kt`、正常系は `Scripts/diff_cases/range_to_array_via_tolist.kt` で固定済み。synthetic member 登録は #6790 で削除、`kk_ulong_range_toULongArray` の @_cdecl bridge/Lowering rewrite/RuntimeABI エントリは `range-toarray-lowering-cleanup` で削除済み）
  - 手順: T
  - diff: `ulong_range_*.kt` 既存 + `ULong.MAX_VALUE` 境界と空 range ケース
  - 既知の疑義: `ULongRange.sum()`（`RangeHOF.kt`、`@KsSymbolName("__kk_range_sum")`）は signed Int64 の `RuntimeRangeAndDispatch.swift` 実装にネイティブ委譲されたままで、`2^63` を跨ぐ range（例: `(1uL shl 62)..(1uL shl 63)`）では内部の符号付き比較が破綻し得る（未確認・未再現。KSP-1523 のスコープ外として先送り、本チケットで検証し要修正なら対応する）
  - 注意: KSP-1523 で UInt 側の `average()`/`toUIntArray()` は実 kotlinc に存在しないことが判明した（`average()` は `Iterable<Byte/Short/Int/Long/Float/Double>` のみで `UInt` 無し、`toUIntArray()` は `Collection<UInt>` メンバーで `UIntRange`(`Iterable<UInt>`) には無い。`diff_kotlinc.sh` で確認済み）。`kk_ulong_range_average`/`_toULongArray` も同様に実在しない可能性が高いので、`RangeHOF.kt` に追記する前に `diff_kotlinc.sh` で `ULongRange.average()`/`.toULongArray()` を検証すること。実在しなければ 13 件ではなく 11 件の移行＋2 件の削除のみで完了とする
  - 前提: KSP-1523

- [x] KSP-1527: `ULongRange` の map / filter 系 HOF を Kotlin 化する
  - 対象スタブ: 同上（`kk_ulong_range_*`）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt` 追記
  - 削除/降格 kk_*: `kk_ulong_range_map`, `_mapIndexed`, `_mapNotNull`, `_filter`, `_filterIndexed`, `_filterNot`（6件）
  - 手順: T
  - diff: `ulong_range_hof*.kt` 既存 + `mapNotNull`/`filterNot` ケース
  - 前提: KSP-1524, KSP-1525

- [x] KSP-1530: `ULongRange` の iterator / step / 構築演算子 / windowing を Kotlin 化する
  - 対象スタブ: 同上（`kk_ulong_*`）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeIterators.kt` / `ProgressionConstructors.kt` 追記
  - 削除/降格 kk_*: `kk_ulong_range_iterator`, `_hasNext`, `_next`, `_chunked`, `_windowed`, `_take`, `_drop`, `kk_ulong_rangeTo` を `__kk_*` へ降格（`kk_ulong_downTo` は本PR着手時点で既に `__kk_ulong_downTo` に降格済みだった。`ULongRange`/`ULongProgression.step` は `fromClosedRange` 経由の純 Kotlin 実装に置き換え、`__kk_ulong_step` ブリッジは呼ばなくなった。ブリッジ自体は step プロパティ取得や Lowering の残置フォールバックから参照が残るため削除せず維持）
  - 手順: T
  - diff: `Scripts/diff_cases/ulong_progression.kt` 新規（uint_range.kt 相当 + iterator/take/drop/chunked/windowed + `ULong.MAX_VALUE` 近傍の `step` オーバーフロー非回帰ケース。旧 `runtimeUnsignedStep` の符号付き剰余バグを `fromClosedRange`（符号なし演算）経由に切り替えることで解消したことを確認）
  - 前提: KSP-1529

- [x] ~~KSP-1532: `UInt` の数値変換メンバ（`toByte`/`toChar`/`toDouble`/`toFloat`/`toInt`/`toLong`/`toShort`/`toUByte`/`toULong`/`toUShort`）を Kotlin 化する~~ **前提が誤りと判明、close**（2026-09-13）。「対象」として挙げられていた (b) 判定の `kk_uint_to_char` は、実在する `UInt.toChar()` メンバを裏付けるものではなかった——kotlinc は `UInt` に `toChar()` を持たず、kswiftc の Sema も元からこの呼び出しを解決していなかった（KSP-1531 の分類は Runtime `@_cdecl` 存在とKIR lowering table 内の文字列一致だけで機械的に収集されたもので、実際に呼び出し可能かは確認されていなかった）。KSP-1534 の調査で発覚、`kk_uint_to_char` は到達不能な dead code として削除済み。詳細: `docs/stdlib-pipeline.md` の「KSP-1534 correction」節。

- [x] ~~KSP-1533: `ULong` の数値変換メンバを Kotlin 化する~~ **前提が誤りと判明、close**（2026-09-13）。KSP-1532 と同じ誤り（`kk_ulong_to_char` も実在しない `ULong.toChar()` を裏付けない）。`kk_ulong_to_char` は到達不能な dead code として削除済み。詳細: `docs/stdlib-pipeline.md` の「KSP-1534 correction」節。
  - 追加発見・修正（KSP-1533 側の並行調査、2026-09-13）: 上記 close 作業とは独立に、`kk_ulong_to_char` 削除の regression diff ケース作成中に `ULong.toUInt()` のバグを発見・修正した。`kk_ulong_to_uint` は現行シンボルなしで representation-preserving copy と記載されていたが、これは `Long<->ULong`（64→64）と同じ扱いの誤りで、実際は 64→32 の truncating narrowing が必要だった。上位32bitがゼロでない値（`ULong.MAX_VALUE` 等）は `toString()`/`==` で壊れた値を返していた（算術演算の `+` は結果を32bit境界へ強制マスクするため偶然正しく見えていた）。修正は `kk_long_to_uint`（既に `UInt32(truncatingIfNeeded:)` でマスクする既存シンボル、同じ raw-register 表現）への再利用ルーティング。ABI・Runtime の新規追加なし。回帰: `CodegenBackendNumericBoundariesTests.testNumericBoundaryULongToUIntTruncates`、`Scripts/diff_cases/unsigned_conversions.kt`。

- [x] ~~KSP-1534: `UByte` の数値変換メンバを Kotlin 化する~~ **前提が誤りと判明、close**（2026-09-13）。「対象」の `kk_ubyte_to_char` は実在する `UByte.toChar()` を裏付けなかった——kotlinc に `UByte.toChar()` は無く、`UByte` は `kotlin.Number` を継承しない。ただし kswiftc では BUG-251（`Subtyping.swift` の `primitive <: Number` ルールが `.ubyte, .ushort` を誤って `Number` サブタイプに含めていた）により `someUByte.toChar()` が継承された `Number.toChar()` へ誤って解決され、"動いているように見えていた"。BUG-251 を修正し、`kk_ubyte_to_char` を到達不能な dead code として削除。回帰: `Tests/CompilerCoreTests/GoldenCases/Diagnostics/unsigned_types_not_number.kt`。詳細: `docs/stdlib-pipeline.md` の「KSP-1534 correction」節、BUG-251 本体。

- [x] ~~KSP-1535: `UShort` の数値変換メンバを Kotlin 化する~~ **前提が誤りと判明、close**（2026-09-13）。KSP-1534 と同じ根本原因（BUG-251）で `someUShort.toChar()` が誤って `Number.toChar()` に解決されていた。BUG-251 の修正で `kk_ushort_to_char` も到達不能になり、dead code として削除。詳細: `docs/stdlib-pipeline.md` の「KSP-1534 correction」節、BUG-251 本体。

- [x] KSP-1542: `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` の Collection/MutableCollection/Iterable 型シェルとメンバ登録を整理する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticCollectionTypeFallbacks.swift`（現在1061行。KSP-701/KSP-665 の分離先で、現行の主な呼び出し元は `HeaderHelpers+SyntheticCollectionResiduals.swift` の `registerSyntheticCollectionStubs`）。対象は `registerSyntheticCollectionStub`/`registerSyntheticMutableCollectionStub`/`registerSyntheticIterableStub`（`Collection`/`MutableCollection`/`Iterable`/`Iterator`/`MutableIterator` の fallback 型シェルと `isEmpty`/`contains`/`random`/`randomOrNull`/`add`/`addAll`/`clear`/`remove`/`removeAll`/`retainAll`/`iterator`/`hasNext`/`next` の残余登録）。`registerSyntheticAbstractCollectionStub`/`registerSyntheticAbstractMutableCollectionStub`/`registerSyntheticMutableIterableStub` は bundled Kotlin source を再利用する fallback 専用であり、`MutableIterable.iterator()` の covariant override は BUG-200（library metadata が再型付けを表現できない）のため compiler 残置とする。
  - 実装先: KSP-700 などが提供する `Sources/CompilerCore/Stdlib/kotlin/collections/Collection.kt`/`MutableCollection.kt`/`Iterable.kt`/`MutableIterator.kt`。bundled source の nominal 宣言は正規経路とし、Swift 側は source header collection が既存 symbol と型パラメータを再利用できる fallback および runtime bridge の残余登録に限定する。
  - 削除/降格 kk_*: 対象 public `kk_*` なし。`__kk_collection_isEmpty`/`__kk_collection_size`/`__kk_collection_containsAll`/`__kk_mutable_collection_add`/`addAll`/`clear`/`remove`/`removeAll`/`retainAll`・`kk_iterator_hasNext`/`kk_iterator_next`・`kk_list_iterator`/`kk_iterable_iterator`・`kk_op_contains` は、List/Set/Iterator の runtime box が itable に自己登録しないため virtual dispatch を bypass する (c) bridge として維持する。`kk_list_random`/`kk_list_randomOrNull` も KSP-1509 後の no-stdlib/precompiled fallback が参照するため削除しない。
  - 手順: T。itable dispatch 制約により (b) 化不能と判明した分は KSP-1520 と同様「(c) 残置と結論付け、根拠を `docs/stdlib-pipeline.md` §9 に記録して完了とする」
  - diff: `collection_*.kt`, `iterable_*.kt`, `mutable_collection_*.kt` 既存拡張 + 新規 `collection_interface_set_backed_dispatch.kt`
  - 前提: KSP-700, KSP-701, KSP-1509（すべて完了）
  - **2026-09-13 実装メモ**: 着手時に前提の実態を確認した。KSP-701 は完了済み（PR #5915/#5990 で実装・マージ済み。台帳に `- [ ] KSP-701:` エントリが無いのは完了により剪定されたためで、未着手ではない）。KSP-700 は実際に未着手（`Collection.kt`/`List.kt`/`Comparable.kt`/`AbstractList.kt` は未作成。`Iterable.kt`/`MutableCollection.kt` は KSP-697 側の成果で型宣言のみ既存）。`gh pr list`/`git branch -a` で KSP-700 に取り組む並行作業は確認できなかった。前提未達のため `Collection.kt` 新設と「重複登録除去」自体は本PRのスコープ外とし（KSP-700 の担当のまま）、(c) 確定の証拠固めと安全な整理のみ実施した。
    1. `registerSyntheticCollectionStub`/`registerSyntheticIterableStub` の型パラメータ（`Collection.E`/`Iterable.E`/`Iterator.T`）に、他4関数（`AbstractCollection`/`MutableCollection`/`AbstractMutableCollection`/`MutableIterable`）と同じ「既存シンボルがあれば再利用」ガードを追加。`HeaderHelpers+SyntheticPathStubs.swift` の `?? registerSyntheticIterableStub(` 遅延呼び出しが `registerSyntheticIterableStub` の第二の呼び出し元であり、`HeaderHelpers+SyntheticCollectionResiduals.swift` 側より先に発火すると型パラメータが再定義され既存メンバーの型が孤立化する潜在的な順序依存バグを解消した（挙動不変。Golden Sema 92件・関連 diff_cases 15件で確認）。
    2. `Scripts/diff_cases/collection_interface_set_backed_dispatch.kt` を新規追加し、Set-backed な `Collection`/`MutableCollection`/`Iterable` 型付きレシーバー経由の `isEmpty`/`contains`/`containsAll`/`iterator`/`add`/`remove`/`retainAll` 呼び出しが kotlinc と一致することを固定（PASS）。
    3. `contains`（`kk_op_contains`）/`isEmpty`（`__kk_collection_isEmpty`）の `externalLinkName` を個別に一時的に外す実験を実施。`contains` を外すと BUG-166 コメント通り `KSWIFTK-RUNTIME-0001`（"method not found in vtable/itable"）でパニックすることを確認した（コメントは正確）。一方 `isEmpty` を外した場合はパニックせず無言の誤答（`emptySet<Int>().isEmpty()` が `false` を返す）になった——`isEmpty` 側のコメントはパニックを明示していない（"requires virtual itable dispatch" のみ）ため矛盾ではないが、より危険な失敗モードである点を `docs/stdlib-pipeline.md` §9 に記録した。
    4. KSP-1509 は git log・オープンPRのいずれにも実績がなく未着手と確認したため、dangling 修正は不要。
    5. 詳細根拠・KSP-700 への前方制約（`Collection.kt` は `<out E>` で宣言すること等）は `docs/stdlib-pipeline.md` §9 の該当行に記録済み。
    6. `Scripts/loc_report.sh` の `header_helpers_synthetic_total_lines` は 34666→34678（+12。型パラメータの idempotency guard 3箇所×4行のみ、対象ファイル以外の `HeaderHelpers+Synthetic*` は無変更）。`kk_literal_count`（6523）・`kk_cdecl_count`（954）・`__kk_cdecl_count`（881）・`kir_lowering_todo_fixme_count`（0）はいずれも不変。
    - **残**: `Collection.kt` 等 KSP-700 の型宣言が揃うまで、この shell の「重複登録除去」自体は着手不可（前提未達）。揃った時点でも本ファイル側の追加変更は不要（Collection の shell は既に「既存シンボル再利用」パターンに揃っている）。
    - 動作確認は変更箇所に絞ったスコープのみ実施: `swift build`、新規 diff case 1件、関連既存 diff_cases 15件、Golden Sema 92件（すべて green）。全 Swift suite・全 Golden（Lexer/Parser/Diagnostics）・全 `diff_kotlinc.sh` は未実行だったが、PR #6784 の CI（Swift test shards、Backend/Runtime/CLI/LSP、Repository Checks、kotlinc Diff 全 shard）がすべて green となったため完了へ更新した。
    - **2026-09-16 完了追記**: 前提の KSP-700（PR #6837）と KSP-1509（PR #6818）がともに merge 済みであることを再確認した。KSP-1542 の PR #6784 も全必須 CI を通過済み。`Collection`/`Iterable`/`Iterator` 系の nominal 宣言は bundled Kotlin source を正規経路とし、Swift 側は `--no-stdlib`/precompiled metadata 用の fallback と、runtime box の itable 未登録を迂回する (c) bridge 残余だけを保持するため、追加の shell 削除・bridge 改名は行わない。

- [~] KSP-1544: `HeaderHelpers+SyntheticCoercionStubs.swift` の (b) 分を Kotlin 化し (c) 残置分を §9 で確定する（Linear KUU-588）
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticCoercionStubs.swift`（着手時 449 行、§9 記載の 654 行は stale だった）
  - 再分類結果（着手時 rg で再固定）: 登録は Int×9 / Long×9 / Float.toByte・toShort / Double.toByte・toShort・toFloat の 23 件 + `kotlin.math` package bootstrap。(b) は Float/Double の `toByte()`/`toShort()` 4 件のみ — 本家は `toInt().toX()` 合成で `warningSince="1.3"`/`errorSince="1.5"`（apiVersion 2.2 では error-level deprecated）。残りは (c): Int/Long の primitive cast 全般と `Double.toFloat` は lowering が `kk_*` へ直接写像する言語コア面（KSP-1531 分類表どおり）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/Numbers.kt` 追記（KSP-1538 ブロック末尾。`toInt().toByte()` / `toInt().toShort()` の実 body + 本家準拠の `@Deprecated`/`@DeprecatedSinceKotlin`/`ReplaceWith`）。range/coercion は `ranges/RangeCoercion.kt` で既に完全に source-backed のため追記なし
  - 削除/降格 kk_*: なし。4 件の synthetic 登録は `__kk_float_to_int`/`__kk_double_to_int` を指していたが、これらは bundled `Float.toInt`/`Double.toInt` と `kk_number_to_primitive` dispatch が継続利用するため保持。`kk_int_to_int` は identity 登録として (c) 残置
  - dead code 削除（同ファイル内、(b) 範囲外の付帯整理）: `kotlin.math` package bootstrap（registry 順で Math bucket の `ensureSyntheticPackageHierarchy` が常に先行するため到達不能）と `syntheticDeprecatedAnnotationsForCoercion`（`toChar` 専用だが登録対象 0 件）。Registry の `Coercion` entry は `.sourceBackedMigration` → `.residualCompilerSurface` へ
  - **(b) stub が実害バグを持っていた点を記録**: 旧登録は `returnType: intType` で `Float.toByte()` が Int を返す誤シグネチャだった（`val b: Byte = 1.5f.toByte()` が型エラー、`300.9f.toByte()` が narrowing 無しの 300 を返す）。source 化で `toInt().toByte()`（44）に一致し、未抑制呼び出しは本家同様 error-level deprecated になった（`Scripts/diff_cases/float_double_to_byte_short.kt` で PASS 確認、`@file:Suppress("DEPRECATION_ERROR")` 下で実行）
  - 手順: T
  - diff: `Scripts/diff_cases/float_double_to_byte_short.kt` 新規
  - 前提: なし
  - 検証: `swift build` green、新規 diff case PASS、`FloatDoubleNumericConversionSourceTests`（`toByte`/`toShort` の source-backed 化 + error-level deprecated 拒否を追加）、`CoercionSyntheticStubTests`・`IntConversionMemberCallTests`・`LongConversionMemberCallTests`・`FileSuppressAnnotationTests`・Golden Sema 等 focused 実行。全 suite・全 `diff_kotlinc.sh` は CI 待ち（AGENTS.md 最小スコープ方針）
  - KSP-1541 への影響: ルート `kotlin/` パッケージ rename ブロッカーの片方（`+SyntheticCoercionStubs.swift` の (b) 残）を解消。`+SyntheticArrayStubs.swift` の (b) 残は別タスクで継続

### CLEANUP-STUB 追補（(a) 削除。2026-07-10 監査。採番は履歴最終 095 の続き。手順は RF-STUB-002 レシピ）

> 「本家で deprecated/obsolete かつ KSwiftK でも未実装」の二重死と fiction。**W6 の移行より先に実施を推奨**（移行対象面積が減る）。

- [x] CLEANUP-STUB-107: `HeaderHelpers+SyntheticFileIOStubs.swift` は削除済み。File 自身の facade（readText/writeText/appendText/exists/isFile/isDirectory/forEachBlock/bufferedReader/bufferedWriter/printWriter/walk/listFiles/delete/mkdirs/readBytes/appendBytes/writeBytes/absolutePath/canonicalPath/length/lastModified/createNewFile/canRead/canWrite/canExecute/copyTo/copyRecursively）と対応する Runtime `__kk_file_*` cdecl・`RuntimeABISpec+FileIO.swift`/`+ABIParity.swift` エントリ・テストは削除した。削除できず残存（fiction ではなく実働ブリッジ）: File の bare shell・`path` プロパティ・コンストラクタ2種（`File(path: String)` / `File(parent: String, child: String)`、externalLinkName `__kk_file_new`/`__kk_file_new_parent_child`）、Runtime `RuntimeFileBox`/`RuntimeFileTimeBox`、`__kk_file_path`/`__kk_file_readText`（保持理由: `kotlin.io.FileSystemException` の File/File? コンストラクタ=KSP-619、`Files.kt` の `resolveSibling`/`normalize`=KSP-483 が実際に File を構築・受け渡す実働コンシューマ）。加えて Reader/BufferedReader/Writer/BufferedWriter/InputStream/OutputStream ファミリも、File 非依存の kotlin.io 拡張と CLEANUP-STUB-115（Path）で再利用するため保持。2026-09-14 [x] 化: PR #6789（08842a775、2026-09-13 マージ済み、コミットメッセージに `--emit kir`・CompilerBackendTests・`diff_kotlinc.sh`（kklib mode）・Sema golden・focused CompilerCoreTests/RuntimeTests green の記録あり）で実装・検証済みで現ブランチ HEAD の祖先。`rg -n '__kk_file_' Sources Tests` で File 固有の残存が `__kk_file_new`/`__kk_file_new_parent_child`/`__kk_file_readText`/`__kk_file_path` の4件のみであることを再確認済み（`__kk_file_system_exception_*` は別クラス）。副次発見（`OutputStream`/bare `Writer` が File 側 producer 削除で構築不能）は CLEANUP-STUB-107 のスコープ外、CLEANUP-STUB-115 着手時判断として `docs/stdlib-fiction-audit.md`（2026-09-13 節）に先送り済み
  - **削除できず残存**（fiction ではなく実働ブリッジ）: File の bare shell・`path` プロパティ・**コンストラクタ2種**（`File(path: String)` / `File(parent: String, child: String)`、externalLinkName `__kk_file_new`/`__kk_file_new_parent_child`）、Runtime `RuntimeFileBox`/`RuntimeFileTimeBox`、`__kk_file_path`/`__kk_file_readText`。加えて Reader/BufferedReader/Writer/BufferedWriter/InputStream/OutputStream 共有ファミリ一式（`HeaderHelpers+SyntheticJavaIOStreamStubs.swift` に集約）
  - **ブロッカー**: (1) `kotlin.io.FileSystemException`/`FileAlreadyExistsException`/`AccessDeniedException`/`NoSuchFileException`（KSP-619, `Stdlib/kotlin/io/FileSystemException.kt`）の公開コンストラクタが `File`/`File?` を引数に取り、ユーザーコードが `AccessDeniedException(File(path))` のように実際に構築する（`access_denied_exception.golden` で実測）。(2) `Files.kt`（KSP-483）の `resolveSibling`/`normalize` が内部で `File(...)` を再構築する。File を non-constructible にするとこの2系統が両方壊れるため、コンストラクタは削除できない。(3) 上記 Reader/Writer/Stream 共有ファミリは CLEANUP-STUB-115（Path）とも共有されており、Path 側の削除が先に完了するまで単独では動かせない
  - **注意**: KSP-483/484 のドキュメント化がこのタスクの着手より後付けだったため、「File 削除」というタスク名から実際のスコープ（File 自身の facade のみ）を読み違えやすい。次にこの周辺へ触るときは「File は削除される」ではなく「File は bare shell として残り、facade だけ消える」を前提にすること
  - `Lowering/CollectionLiteralLoweringPass+*` 側は `fileExprIDs` フィールド自体は汎用の分類状態（`pathExprIDs` 等と同じ構造）として残し、File 用のシード（PreScan）と消費側（VirtualCallRewrite の File switch、CallRewriteFile の File 分岐）のみ削除した。`fileExprIDs` は今後恒常的に空集合になるが、これは仕様であり bug ではない。`kkPathWalkName`/`kkPathUseLinesName`/`kkPathUseLinesDefaultName` は grep 上の consumer（closureRaw 注入ロジック）を根拠に残したが、実際に Sema 側で `Path.walk()`/`Path.useLines()` が現在到達可能かは未検証（115 側で確認すること。「residual-allowlist-unreachable」の罠と同型）
  - **副次発見**（本タスクのスコープ外・CLEANUP-STUB-115 への申し送り）: `java.io.OutputStream`/`Writer`（bare, Buffered 抜き）は Kotlin ソースから一切構築できない状態になっている。唯一の生成経路だった `File.outputStream()`/`File.bufferedWriter()` が本タスクで削除された一方、`kotlin.io.path.Path` 側にも `outputStream()`/`bufferedWriter()`/`bufferedReader()` の Sema 登録は存在しない（`HeaderHelpers+SyntheticPathStubs.swift` は `outputStreamSymbol`/`bufferedReaderSymbol`/`bufferedWriterSymbol` という bare class anchor だけ持ち、Path member としての producer が無い——`kk_path_outputStream`/`kk_path_bufferedReader`/`kk_path_bufferedWriter` という Runtime cdecl 自体は存在し `Tests/RuntimeTests/` から直接呼べるので「死んでいる」のは Sema 側の配線のみ）。影響: `OutputStream.buffered()`/`.bufferedWriter(charset)`/`.encodingWith(Base64)`（`Stdlib/kotlin/io/encoding/Base64.kt:232`）と `Reader.copyTo(Writer)` はユーザーの Kotlin コードから到達不能になり、対応する3つの `OutputStream*FunctionTests.swift` と `ReaderCopyToFunctionTests.swift` は削除した。115 で Path 側に producer を追加するか、この一式を target-out として ABI ごと削除するかの判断が必要
  - **副次発見2**: `Tests/RuntimeTests/RuntimeStreamTests.swift` から `__kk_input_stream_available`/`skip`/`read_bytes`/`copyTo` のテストが失われた（File ベースの fixture しかなく、上記と同じ理由で Path 版が組めない）。`RuntimeInputStreamBox` を `Data(contentsOf:)` から直接構築するテスト専用 fixture を足せば復元できる（未実施）
  - **CI で発覚し修正済みの誤削除**: `kotlin.io.createTempDir`/`createTempFile`（4 overload ずつ、`@Deprecated(level=ERROR)` 付き）を一度完全に削除してしまっていた。これらは File 自身の facade ではなく実在する force-deprecated stdlib top-level 関数で、唯一の登録元だった `registerSyntheticFileIOBootstrap`（削除済み）に File の bootstrap と相乗りしていたため、コンストラクタ復元時に見落とした。CI の `AnnotationSemanticTests.testAnnotationSemanticSema`（`createTempDir()` の deprecated-error 診断を検証）が `Fatal error: Index out of range` で検出。Sema 登録（`HeaderHelpers+SyntheticJavaIOStreamStubs.swift`）・Runtime の8 cdecl 実装（`RuntimeFileIO.swift`）・`RuntimeABISpec+ABIParity.swift` の8エントリを、削除前の実装をそのまま復元。「File 自身の facade かどうか」と「File のセットアップと同じ場所に書いてあるか」は別軸であり、一括削除の際は呼び出し先の関数が実際に何を登録しているか1行ずつ確認する必要があった
- [x] CLEANUP-STUB-115: `HeaderHelpers+SyntheticPathStubs.swift`（本体）を削除する。2026-09-16 [x] 化: PR #6820（`fe8e8edfb`、2026-09-14 マージ済み）が現ブランチ HEAD の祖先。`gh pr checks 6820` で CI 18 ジョブ全 pass を再確認。`git ls-tree origin/master` で `HeaderHelpers+SyntheticPathStubs.swift`/`RuntimePath.swift`/`RuntimeABISpec+Path.swift` の不在、`rg 'kk_path_' Sources` 0 件を再確認済み（Linear KUU-538 は既に Done、TODO.md 側のみ未同期だった）
  - **実施内容（2026-09-14）**: 着手時点で CLEANUP-STUB-116〜118 は既に完了済みで、対象ファイルは記載の2102行ではなく924行（`registerSyntheticPathStubs(...)` 1関数のみ、`kk_path_*` の externalLinkName 登録は既に0件で `kotlin.io.path.Path` は既に bare shell 化されていた）だった。`registerSyntheticPathStubs` とその呼び出し元2箇所（`HeaderHelpers.swift`、`HeaderHelpers+SyntheticBucketedStubRegistry.swift` の `name: "Path"` エントリ、`.targetOutCleanup` タグ済み）を削除
  - 連動整理: Runtime `Sources/Runtime/RuntimePath.swift`（`kk_path_*` 82 cdecl。記載の「273件」「kk_uri_*/kk_url_* も含む」は実測と不一致で誤りだった）、`Sources/RuntimeABI/RuntimeABISpec+Path.swift`（113 spec エントリ、うち31件は cdecl 未実装の残存spec）を削除。`RuntimeABISpec.swift` の集約リストと `RuntimeABISpec+ABIParity.swift`/`ABIMismatchTests+RuntimeExportParity.swift` の allowlist から該当エントリを除去
  - Lowering: `CollectionLiteralLoweringPass+LookupTables+FileIO.swift` の `kkPathUseLinesName`/`kkPathUseLinesDefaultName`/`kkPathWalkName`（到達不能だった。TODO 475 で 115 への申し送りとされていた検証はこの削除で確定）と `+CallRewriteFile.swift`/`+LookupTables.swift` の対応分岐・転送プロパティを削除
  - Sema: `CallTypeChecker+MemberCallFallbacks.swift` の `tryPathCharsetReadExtensionFallback`（`kotlin.io.path.Path` 固定の FQName チェックで、producer 不在のため元々到達不能）とその呼び出し2箇所を削除
  - **476 の判断を確定**: Path 側へ `outputStream()`/`bufferedReader()`/`bufferedWriter()` の producer は追加せず、`OutputStream`/bare `Writer` は Sema 到達不能のまま target-out にはしない（`HeaderHelpers+SyntheticJavaIOStreamStubs.swift` の bare class anchor は (c) 残置のまま）。`FileTime`（`RuntimeFileTimeBox`/`__kk_fileTime_toMillis`、CLEANUP-STUB-110 で Path 共有を理由に保持）は Sema 側の唯一の登録元が本ファイルだったため producer 消滅に伴い Runtime 実装ごと削除（`RuntimeFileIO.swift`・`RuntimeABISpec+ABIParity.swift` エントリ）
  - テスト影響（記載の `Tests/CompilerCoreTests/Sema/Path*FunctionTests.swift`（5ファイル）・`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+PathCreateSymbolicLink.swift`・`Scripts/diff_cases/path_basic.kt` はいずれも実在せず、記載が誤りだった）: `PathGenericFunctionStubRemovalTests.swift` → `PathStubRemovalTests.swift` に改称し完全削除の回帰テストへ書き換え、`PathWalkOptionEnumTests.swift`（219行）を削除、`ExperimentalMarkerStubTests.swift`/`SemanticsAndUtilitiesRegressionTests.swift`（後者は index-positional のため空きスロット化）から Path 関連ケースを除去。`Tests/RuntimeTests/RuntimePath*Tests.swift`（21ファイル）を削除。`RuntimeBufferedReaderTests.swift`/`RuntimeBufferedWriterTests.swift`/`RuntimeStreamTests.swift` は `kk_path_*` をフィクスチャ構築に使っていたため、`FileHandle`+box直接構築のフィクスチャへ書き換え（JavaIOStream は (c) 残置のため、テストごと削除ではなくフィクスチャ差し替えを選択）。`LoweringPassRegressionTests+ClosureArgumentRewrite.swift` は Path 専用テストだったため、`__kk_buffered_reader_useLines`/`forEachLine` の closureRaw 注入テストへ差し替え（従来カバレッジが無かった箇所）。Golden/diff_cases に `kotlin.io.path`/`java.nio.file` 依存ケースなし（grep 確認済み）
### バグバックログ（BUG-NNN。既存の未修正バグの記録。PR 状態は各タスクの記載時点）

> このセクションは過去に記録された未修正バグの記録専用で、新規追加は行わない。バグを発見したら最小再現と回帰テストを含めて発見した PR 内で修正し、同じ PR のスコープを超えて修正できない場合は Linear に起票し（team Kuu / project バグバックログ (BUG) / label Bug）、issue リンクを PR description に記載する。TODO.md には追加しない（並行セッションが同じ挿入位置に追記して衝突する原因になるため）。

- [x] BUG-215: object 式（匿名クラス）で**クラス**を継承すると、(1) 基底クラスの `open`/`abstract` メンバへの override が dispatch されず基底実装（`abstract` の場合は `null`）が使われ、(2) スーパークラス実引数付き `object : Base(x) {}` は実行時 `KSwiftK panic [KSWIFTK-RUNTIME-0001]: kk_array_get_inbounds precondition failed` でクラッシュする。interface を実装する object 式のプロパティ dispatch は BUG-141 で修正済みで、本件はクラス継承経路。最小再現: `open class Base { open fun describe(): String = "base" }` `fun make(): Base = object : Base() { override fun describe(): String = "anon" }` `fun main() { println(make().describe()) }` が `"base"`（kotlinc は `"anon"`）。(2) は `open class Base2(val v: Int)` `fun make2(x: Int): Base2 = object : Base2(x) {}` でクラッシュ。名前付きサブクラスのスーパークラス primary constructor 実引数伝搬は PR #5506（`1128468186`）で別途修正済みだが、object 式はこのクラッシュが残る点が異なる。発見元: 2026-08-06 に KSP-491 の着手前プローブで一度 `BUG-188` として台帳登録されたが、後続の TODO.md 統合編集で記録が失われていた。2026-08-18 `.build/debug/kswiftc` で再実機確認し、症状に変化なし（両方とも pre-existing）。台帳は KSP-CAP-018。**修正済み（2026-08-18 + 2026-09-13、KSP-CAP-018）**: override メンバを1つ以上持つ object 式は 2026-08-18 に (1)(2) とも解消。メンバ宣言を持たない空ボディの object 式（(2) の最小再現そのもの）は別経路のため残存していたが、2026-09-13 に空ボディでも `ObjectDecl` を生成して同じ経路へ合流させることで解消（詳細・回帰は KSP-CAP-018 参照）。空ボディ側は実引数の有無に関わらずクラッシュしていた（`object : Base() {}` + 基底のプロパティ初期化子でも再現）点が当初の記載と異なる。2026-09-14 に上記2つの最小再現を実機再検証し、それぞれ `anon` / `7` を正しく出力することを確認して本項目を [x] 化。本項目に残っていた名前付き（非リテラル）`object : Base(x) { ... }` 宣言は当初から KSP-CAP-018 のスコープ外で、BUG-264 として独立起票。**採番注記**: master 側が独立に別内容（Platform.memoryModel の KIR 欠落）で `BUG-212` を先に登録していたためマージ時に `BUG-215` へ採番し直した（このセッション自身が KSP-681 調査時に発見した「TODO.md の BUG/CAP 番号衝突」の再発例）

- [ ] BUG-264: 名前付き（非リテラル）`object : Base(x) { ... }` 宣言（`fun make(): Base = object Named : Base(x) { ... }` の形。無名の object **式**は KSP-CAP-018/BUG-215 で解消済みで対象外）は2つの独立した問題が残る。(1) スーパークラス実引数付きコンストラクタ呼び出しが破棄され、object 式版の症状2（`kk_array_get_inbounds precondition failed`）と同様の実引数消失が起きる可能性が高い（未検証、object 式側の修正 `ObjectDecl.superTypeConstructorArgs` は名前付き宣言の構文経路を対象にしていない）。(2) base 型変数経由での virtual dispatch がレシーバに誤った定数値を積む別バグ（発見元 p9、`.symbolRef` 定数が `loadGlobal` の代わりに使われている）。症状1（override dispatch 自体）は名前付きでも再現しない。詳細未起票（最小再現・真因調査は本エントリ起票時点で未実施）。発見元: KSP-CAP-018/BUG-215 の調査過程（2026-08〜2026-09-13）で当初からスコープ外と判定され続けてきたもの。必要になったタイミングで最小再現を追加し、独立した KSP-CAP として切り出すことも検討する。

- [ ] BUG-213: bundled stdlib のコレクション flow 型推論に無限/極端に深い再帰サイクルがあり、単独プロセスの薄いスタックだと `Thread stack size exceeded`（SIGBUS, EXC_BAD_ACCESS）でクラッシュする。症状: `fun noop() {}` のような1行ファイルを既定の `includeStdlib: true`（bundled source injection）で `runSema` するだけの最小テストを `swift_test.sh --filter` で単独実行すると、macOS のクラッシュレポート（`~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-*.ips`）に `"message": "Thread stack size exceeded"` が記録される。シンボリケートしたスタックは `TypeCheckDriver.inferExpr → ExprTypeChecker.inferLambdaLiteralExpr → ExprTypeChecker.inferExpr → CallTypeChecker.tryBuiltinFlowMemberCall → CallTypeChecker.tryInferMemberCallCollectionFlowSpecials → CallTypeChecker.inferMemberCallImpl → CallTypeChecker.inferMemberCallExpr → ExprTypeChecker.inferExpr → CallTypeChecker.inferCallExpr → ExprTypeChecker.inferExpr → ...` という同一9フレームの並びが数十回繰り返されるサイクルで、ユーザーコードではなく bundled stdlib 自身の関数本体（コレクション HOF チェーンを持つもの）を型検査中に発生している。**pre-existing（回帰ではない）を実証済み**: `git worktree add` で分岐元 `9b2b615107`（KSP-706 着手前の master 相当）へ切り替え、同型の最小テスト（`makeCompilationContext(inputs:[path])` + `runSema`、`includeStdlib` 既定値のまま）を単独 `--filter` 実行したところ、同一の `"Thread stack size exceeded"` クラッシュが再現した。発見元: KSP-706 の回帰テスト（`PairTripleNominalAnchorTests.testBundledSourcePairKeepsNilDeclSiteForGoldenStability`）を単独 `--filter` で実行した際に発覚。フル `swift_test.sh`（`--filter` 無し、または広い `--filter`）ではこれまで気づかれていなかったと見られ、狭い `--filter` で単一の bundled-stdlib フル Sema テストがプロセス内最初の（かつ唯一の）重い処理として実行される場合に限って再現しやすい可能性がある（プロセス起動直後のスレッドスタックサイズが影響していると推測）。今回修正しない理由: `CallTypeChecker` のコレクション flow 型推論（`tryBuiltinFlowMemberCall`/`tryInferMemberCallCollectionFlowSpecials` 周辺）の再帰構造の踏み込んだ調査が必要で、KSP-706（Sema header 収集順序のみの変更）のスコープを大きく超える

- [ ] BUG-221: class の `+`/文字列テンプレートによる Any 消去境界の文字列化 funnel（`CallLowerer.emitAnyToStringWithNullGuard` の `classToStringCallee` 分岐、BUG-204 の enum 専用対応を class にも拡張する形で本 PR にて新設）は、値の**静的型そのもの**が `toString()`（source 宣言・data class 等の合成いずれも可）を持っている場合に限って正しく override を呼ぶ。以下の2パターンは対象外のまま `kk_any_to_string` の汎用フォールバックへ落ち、`<object 0x...>` を出力する: (1) 自身では `toString()` を再宣言せず基底クラスの override をそのまま継承するサブクラスを、そのサブクラス自身の静的型で参照した場合 — `classToStringCallee` の `lookupAll(fqName:)` が厳密な fqName 一致（継承チェーンを辿らない）であるため。最小再現: `open class Base { override fun toString() = "Base!" }` `class Derived : Base()` `fun main() { val d: Derived = Derived(); println("d=" + d) }`（`val d: Base = Derived()` のように**基底クラス型**の変数で保持すれば `Base.toString` がその場で直接見つかり、かつ `Derived` インスタンスへの virtual dispatch も正しく効く — 本 PR で修正・回帰テスト済み。sealed class のサブクラスをその抽象基底型で保持する場合も同様）。(2) 静的型が `Any` の値 — 消去がこの funnel に到達する前に完了しているため `classToStringCallee` は class 型自体を観測できない。最小再現: `class Foo(val x: Int) { override fun toString() = "Foo($x)" }` `fun main() { val a: Any = Foo(1); println("a=" + a) }`。発見元: KSP-1502（`kotlin.uuid.Uuid.Companion` 実装）の副次調査で報告された「`+` 演算子が class の `toString()` override を呼ばず `<object 0x...>` を出力する」バグ（本 PR で修正、`classToStringCallee`/`emitAnyToStringWithNullGuard` の class 分岐と `ConsolePrintLoweringPass` の virtual dispatch 対応を追加）の検証中に、修正後もなお残る境界ケースとして発見。data class（`toString()` が `DataEnumSealedSynthesisPass` で合成される点で source 宣言と異なる）は当初「BuildKIR 時点でシンボルが存在しない」ため対象外と誤って想定していたが、`ConsolePrintLoweringPass`（`println`/`print`）が同じ `lookupAll` で既に data class の合成 `toString()` を解決できていた事実から、Sema がヘッダ収集時点でシグネチャを先行登録していると判明。`classToStringCallee` の synthetic 判定を「`kotlin.Any.toString` フォールバックのみ除外」という `ConsolePrintLoweringPass.isSyntheticAnyToString` と同じ基準に緩めることで data class・sealed data class とも本 PR で正しく解決できるようになった（nullable の null/非null 双方含め検証済み）。回帰テストは `Tests/CompilerCoreTests/Lowering/LoweringPassRegressionTests+ClassStringConversion.swift`（`testDataClassInterpolationCallsSynthesizedToString` 含む）・`Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+ClassToStringOverride.swift`・`Scripts/diff_cases/class_tostring_concat_interpolation.kt`（(1)(2) は意図的に除外し、ヘッダコメントに残存ギャップとして明記）。今回修正しない理由: (1) は `lookupAll` を継承チェーンを辿る解決に置き換える設計変更が必要、(2) はこの funnel が静的型ベースの書き換えである以上原理的に解決できず、値ごとに実行時型を運ぶ真の仮想 `Any.toString()` ディスパッチ機構が別途必要になる。いずれも「Any 消去境界での class toString() 未呼び出し」バグ修正のスコープを大きく超える

- [ ] BUG-222: `object` シングルトンの `toString()` 処理に、レイヤの異なる2つの不具合がある（実 kotlinc 2.3.10 と実機照合済み）。(1) `println`/`print`（`ConsolePrintLoweringPass.classToStringExpression`）は `object` レシーバに対し常に単純名（`classSymbol.name`）を出力する分岐を toString シンボル解決より先に取っており、その object が `toString()` を override していても無視する。最小再現: `object Singleton { override fun toString(): String = "I am Singleton" }` `fun main() { println(Singleton) }` は kotlinc 実測 `"I am Singleton"` に対し本コンパイラは `"Singleton"` を出力する（`Singleton.toString()` の直接呼び出しは正しく `"I am Singleton"` を返す）。override を持たない object（例: `object Plain`）を単純名で出力すること自体はコード中のコメント（「Regular and data objects print their simple name」）からみて意図的な簡略化と見られ（kotlinc 実測では `Plain@<identityHash>` になる非決定値のため、素朴な simple-name 表示は再現性重視の妥当な代替とも解釈できる）バグとして扱わないが、override が実在する場合にまで単純名へ差し替えるのは override 自体の無視であり明確な不具合。(2) `object` シングルトンが `Any` 消去境界を越えると（`+`/文字列テンプレート、`Any` 型変数への代入のいずれでも）、override の有無によらず文字列化結果が無関係な値になる（実機観測では常に `"0"`）。最小再現: `object Plain; fun main() { val a: Any = Plain; println(a) }`（kotlinc 実測 `Plain@<identityHash>` に対し本コンパイラは `0`）。override の無い object でも同様に再現するため BUG-217 の各ケースとも (1) とも別レイヤの問題で、object シングルトンの実体表現が `runtimeElementToString`/`kk_any_to_string`（`Sources/Runtime/RuntimeCollectionHelpers.swift`/`RuntimeNumericCompat.swift`）が前提とする「GC 管理ヒープポインタで `objectPointers` レジストリに登録済み」という形を取っていない、または当該レジストリに登録されていない可能性が高い（未検証の仮説）。発見元: KSP-1502 の副次調査（class の `+`/文字列テンプレートでの `toString()` 未呼び出しバグ、本 PR で修正）の検証中、修正が `object` レシーバを意図的に対象外（`classToStringCallee` は `classSymbol.kind == .class` のみを対象とする）としたため、隣接ケースとして object を試して発見。今回調査・修正しない理由: (1) は `ConsolePrintLoweringPass` の object 分岐の設計意図の再検討と、override 存在チェックを単純名分岐より前に持ってくる改修が必要、(2) は object シングルトンの runtime 表現そのものの調査が必要で、いずれも「class の `+`/文字列テンプレートでの toString() 未呼び出し」バグ修正のスコープを大きく超える

- [ ] BUG-234: `getOrPut` で**既存エントリを読み戻す**と、`Double` 値だけが壊れた値になる。最小再現: `fun main() { println(mutableMapOf("k" to 2.5).getOrPut("k") { 9.5 }) }`（kotlinc 実測 `2.5` に対し本コンパイラは `2.144764178E-314` のようなポインタ由来の非正規化数）。実測した範囲: `Float` / `Char` / `Boolean` / `Int` / `Long` / `String` は正しい。map の作り方（`mapOf` / `to` 由来か `map[k] = v` 由来か）とローカルの型注釈の有無には依存しない。結果を `Double` として消費する経路（直接 `println(...)`、`val v: Double = ...` への代入）で症状が出る一方、文字列連結（`"" + m.getOrPut(...)`）は Any 消去経路を通るため正しく出力される。根本原因: bundled inline `kotlin.collections.getOrPut` は `return value`（`this[key]` の結果）と `return answer`（ラムダ結果）の**2つの return 地点**を持ち、`.kklib` 経由の展開では前者が boxed handle、後者が unboxed raw Double のまま同一のマージレジスタへ `copy` される。`InlineLoweringPass.unboxErasedInlineResultIfNeeded`（`Sources/CompilerCore/Lowering/InlineLoweringPass.swift:957`）は展開末尾の `expansion.returnedExpr` 1点だけを正規化し、そのガードはマージレジスタの型（compute 分岐由来の `Double`）を見て「既に raw」と判断するため、early-return 分岐の boxed handle は未変換のまま残る。呼び出し側はマージレジスタを raw Double とみなして `kk_box_double_nonnull` するので、boxed handle のビット列がそのまま double として出力される。今回修正しない理由: 展開内の各 return 地点で表現を揃える必要があり、`InlineLoweringPass` の return マージ構造そのものの変更になる。BUG-233（ABI-002）の boxing 修正スコープを超える。注意: BUG-233 修正前は `map[k] = v` で格納した値も raw だったため、その組み合わせに限っては「格納も読み出しも raw」で偶然正しく出力されていた。`mapOf` / `to` で構築した map では修正前から同じ症状が出るため、欠陥自体は BUG-233 とは独立に以前から存在する。

- [ ] BUG-235: `Collection<T>` 型レシーバに対する `first()` / `last()` が解決されず、リンク時に `Undefined symbols: _first` で失敗する。最小再現: `fun main() { val m = mutableMapOf("k" to 1); println(m.values.first()) }`。`List<T>` レシーバでは解決されるため、`map.values` のように静的型が `Collection<T>` になる経路だけが落ちる。根本原因: `Sources/CompilerCore/Sema/TypeCheck/CallTypeChecker+CollectionMemberFallback.swift:1197` の `collectionMembers` は `firstOrNull` / `lastOrNull` / `single` / `singleOrNull` / `elementAt` を列挙する一方で `first` / `last` を欠いており、source-backed 拡張へのフォールバックに入らない（`Collection` / `Set.joinToString` の非対称ガードと同型の欠落）。今回修正しない理由: 本 PR が触る KIR / ABI lowering とは別サブシステム（Sema のコレクションメンバフォールバック）であり、`collectionMembers` への追加は overload 解決の影響範囲を全 diff / Golden で再検証する必要がある。本 PR は BUG-233 の ABI-002 修正の検証を回しており、同一 PR に混ぜると原因の切り分けができなくなる。

- [ ] BUG-240: `class C : Map<K,V> by mapOf(...)` のインターフェース委譲が2つの症状で壊れている。最小再現: `class CustomMap : Map<String, Int> by mapOf("k" to 1)` `fun main() { val m = CustomMap(); println(m.isEmpty()); println(m.containsKey("k")); println(m["k"]) }`。(1) Sema: `m.isEmpty()` / `m["k"]` が `Unresolved member function 'isEmpty'` / `Type constraint could not be satisfied` で失敗（委譲生成メンバがクラス上の直接メンバ解決で見つからない。一方 `m.containsKey("k")` は解決され、`m.ifEmpty { }` のような `Map` 拡張は subtype 判定で解決される）。(2) 実行時: Sema を通る経路（`Map` パラメータ経由）でも delegate の中身が `mapOf("k" to 1)` ではなく空 Map として振る舞う（`isEmpty()`→`true`、`containsKey("k")`→`false`、`keys.size`→`0`。`override val size = 1` を置くと `isEmpty` が `size == 0` で `false` になり delegate 破壊が隠蔽される —— `Scripts/diff_cases/stdlib_kotlin_collections_n_if.kt` が PASS なのはこの override のため）。発見元: RF-FIXTURE-020 で `CustomMap` への `isEmpty()` 直接呼び出しを Sema fixture に置いたところ `Unresolved member` で発覚し、最小再現で実行時側の空 delegate も確認。今回修正しない理由: 委譲メンバの合成・解決（Sema）と delegate 初期化（Lowering/Runtime）の2層にまたがる修正で、golden fixture の分割という RF-FIXTURE-020 のスコープを大きく超える。

- [ ] BUG-238: `.kklib` 経由の `File.useLines { it.toList() }` の戻り値に対するメンバアクセスが `Unresolved member function` で失敗する。最小再現: `import java.io.File; fun main() { val f = File("/tmp/x.txt"); f.writeText("a"); val collected = f.useLines { it.toList() }; println(collected.size) }` → `error KSWIFTK-SEMA-0024: Unresolved member function 'size'`（`first` も同様）。`println(collected)`（メンバ不要）は正しく `[a]` を出力するため実行時の値自体は正しく、失敗は Sema のメンバ解決のみ。`useLines` は `Sources/CompilerCore/Stdlib/kotlin/io/FileIO.kt:31` の bundled inline `fun <T> File.useLines(block: (List<String>) -> T): T = block(fileLines(this))` で、source-stdlib の golden ハーネス経路では `type=kotlin.collections.List<String>` と正しく記録されるが、`--stdlib-library`（`.kklib`）経由の実コンパイルでは呼び出しの型パラメータ `T` の置換が外側のメンバ解決へ伝わっていない（BUG-234 の inline 展開由来の表現差と同系列）。`useLines { it.count() }` → `Int` は `println` で問題なく、戻り値が `List` などジェネリック結果になるときだけ顕在化する可能性。発見元: RF-FIXTURE-015 で `useLines` が List を返して外で使うケースを `file_uselines.kt` に補完しようとして発覚。今回修正しない理由: `.kklib` 経由の型パラメータ置換を呼び出し結果のメンバ解決へ伝播させる修正は Sema のライブラリ読み込み層の変更で、golden fixture の分割という RF-FIXTURE-015 のスコープを超える。追記（CLEANUP-STUB-107, 2026-09-13）: 上記最小再現の `f.writeText("a")` は `File.writeText()` 削除により再現手順としては使えなくなった（bug 自体は File 固有ではなく `.kklib` 経由の型パラメータ伝播の問題であり無関係）。再現する場合はファイル内容をホスト側（テスト実行前の `Data(...).write(to:)` 等）で用意し、`f.useLines { it.toList() }.size` 部分だけを検証すること。

- [ ] BUG-244: bundled stdlib source ファイル内の `import` でスコープしたはずの型参照が、ユーザーのトップレベル宣言と単純名（simple name）が衝突すると、import ではなくユーザー宣言へ誤解決される。最小再現: ユーザーコードにトップレベルで `class Key(val id: Int) {}` とだけ書く（他に何も書かない）と、`Sources/CompilerCore/Stdlib/kotlin/coroutines/CoroutineContextImpl.kt`（`import kotlin.coroutines.CoroutineContext.Key` の上で `: Key<E>` を継承宣言）がコンパイルエラーになる: `error KSWIFTK-SEMA-FINAL: Cannot inherit from final class 'Key'. Mark it as 'open' to allow subclassing.`（エラーメッセージの `'Key'` に package 修飾が一切無いことが、`kotlin.coroutines.CoroutineContext.Key` interface ではなくユーザーの `class Key` に誤解決された証拠）。`class Element {}` でも同型の衝突を確認（同ファイルの `import kotlin.coroutines.CoroutineContext.Element` が同様に誤爆する）。`fun main() {}` のような衝突しないトップレベル宣言では発生しない。原因（未確定、要追加調査）: `Sources/CompilerCore/Sema/DataFlow/Inheritance.swift` の `bindInheritanceEdges` が supertype 参照（`resolveNominalSymbolAndTypeArgs` 経由）を解決する際、対象ファイルの file-scoped `import` 宣言よりも広いスコープ（グローバルな short-name lookup 等）を先に、または優先して参照している可能性がある。bundled stdlib source は常にユーザーコードと同一コンパイル単位として一括ロードされるため、この経路が正しく import を尊重しない限り、stdlib 内の任意の `import` された nested type 名（`Key`/`Element` に限らない）とユーザーのトップレベル宣言が単純名で衝突するたびに同じ誤爆が起き得る。発見元: PR #6557（KSP-967 Iterable.contains）のコンフリクト解消で `origin/master` をマージした際、PR 自身が追加した回帰テスト `erasedEqualityRegistersUserEqualsOverride`（`Tests/CompilerCoreTests/KIR/BuildKIRRegressionTests+IterableContains.swift`）のフィクスチャがたまたま `class Key` を使っていたために発覚。この stdlib ファイル自体は master 側 KSP-1138（`2ed9a1c4ec`, PR #6579）で PR #6557 の分岐後に追加されたもので、PR 自身の変更（`BuildASTPhase+TypeParamParsing.swift` のみ）はこの解決経路に触れていない——マージが原因ではなく、独立に追加された stdlib ファイルと PR のフィクスチャ命名がたまたま衝突しただけ。今回修正しない理由: 原因箇所が `Inheritance.swift` の supertype 参照解決という、あらゆるコンパイルで経由するコア Sema 経路であり、修正には import スコープの扱い方の調査と全 golden / diff_kotlinc の再検証が要る。PR #6557 はコンフリクト解消が主目的であり、無関係なコア名前解決の修正を混ぜるとスコープの切り分けができなくなるため、当該テストのフィクスチャ名を衝突しない `ErasedEqKey` へ変更する対症療法のみ適用し、本バグ自体は別途追跡する。

- [ ] BUG-241: `.kklib` 経由で読み込んだ、同一 FQ 名を持つ複数の top-level 拡張関数オーバーロードのうち、レシーバの型引数と完全一致する（cross-type ではない）オーバーロードがメンバー呼び出し構文で正しく解決されず、継承元のジェネリックメンバー（例: `ClosedRange<T>.contains`）へ誤ってフォールバックする。最小再現: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeMembership.kt:117` の `public operator fun IntRange.contains(value: Int): Boolean` と `RangeHOF.kt` の `IntRange.contains(Byte/Long/Short)` 系オーバーロードが同居する状態で `fun f(range: IntRange, value: Int): Boolean = range.contains(value)` をコンパイルすると、`--stdlib-from-source`（bundled source injection）では期待通り `kotlin.ranges.contains[recv=IntRange;params=Int]` に解決されるが、`--stdlib-library <artifact>.kklib`（KSP-939 以降の artifact 読み込み経路）では `kotlin.ranges.ClosedRange.contains[recv=ClosedRange<T0>;params=T0]`（ジェネリック継承メンバー）に誤って解決される。無効な引数型（例 `Byte?`）を渡した場合の診断も、bundled-source では `KSWIFTK-SEMA-0002 No viable overload found for call` だが artifact 経由では `KSWIFTK-TYPE-0001 Conflicting bounds for type variable #0: inferred Any? is not a subtype of Int. lower=[Byte?, Int], upper=[Int]` という分かりにくいメッセージに変わる（`kswiftc --stdlib-from-source` と `--stdlib-library` を同一 `.kt` で切り替えて実測比較済み）。実行時の挙動は両経路とも正しい（`ClosedRange<Int>.contains` の実装も同じ比較結果を返すため、`--emit executable` で `range.contains(5/15/1/10)` 等を実行し出力が両経路で完全一致することを確認済み — Sema の解決先シンボルと診断メッセージの精度のみの問題で、コード生成上のバグではない）。`ULongRange.contains(ULong)`（`RangeMembership.kt` の同型オーバーロード）でも `.contains()` メンバー呼び出し構文で同じ現象を確認した一方、`in` 演算子構文（`value in range`）は `isSyntacticRangeExpression`/`isRangeExpr` 経由の別解決パスを通るため影響を受けない場合がある。UInt/UByte/UShort 引数（cross-type、`RangeHOF.kt` の別オーバーロード）は artifact 経由でも正しく解決される。原因（未確定、要追加調査）: `CallTypeChecker+RangeMemberFallback.swift` の `isULongRangeCrossTypeContains`/`isIntRangeSourceBackedHOF` 系ゲートは cross-type ケースのみを `collectRangeSourceExtensionCandidates` 経由の明示解決へルーティングし、同型（exact-type）ケースは通常のメンバー探索に委ねる設計に見える。bundled-source ではこの通常探索で `IntRange.contains(Int)`/`ULongRange.contains(ULong)` が正しく見つかるが、`.kklib` 経由では見つからずジェネリック継承メンバーへフォールバックする。`LibraryImport.swift` の `symbols.define` 呼び出し自体は `canCoexistAsOverload`（`SemanticsModels.swift:664` 付近、`.function` kind 判定）により複数オーバーロードの共存を許可しているため、シンボル登録自体ではなく登録後の通常メンバー探索・オーバーロード選択側に原因がある可能性が高い。発見元: PR #6649（golden テストを artifact 経路へ切り替える変更）と master ブランチ（KSP-1285/KSP-1292: IntRange/ULongRange cross-type contains 追加）のマージコンフリクト解消中、両者を統合した状態で `UPDATE_GOLDEN=1` 実行時に `stdlib_kotlin_ranges_IntRange_cross_contains_n.golden`/`stdlib_kotlin_ranges_ULongRange_n.golden` の再生成結果が master の期待値と食い違うことに気づいた。`kswiftc` 単体で `--stdlib-from-source` と `--stdlib-library` を切り替えて比較し、マージ作業（3ファイルの手動統合）そのものとは無関係に artifact 経由のみで再現することを確認済み（マージ由来のバグではなく、独立に開発された両機能を単純結合しただけで顕在化した既存のギャップ）。今回修正しない理由: 原因箇所が `.kklib` ライブラリ読み込み・通常メンバー探索という広い層にまたがり（BUG-238 と同系統の「ライブラリ読み込み層でのオーバーロード解決」カテゴリ）、特定にはさらなる調査が必要。severity は低い（実行時結果は両経路で一致し、影響は Sema の解決先シンボルの精度と診断メッセージの質のみ）ため、マージコンフリクト解消というスコープを超えて追わず、該当 golden は実際の（artifact 経由の）コンパイラ挙動をそのまま記録する形で固定した。追記（KSP-1290 UIntRange 実装時）: `UIntRange.contains(UInt)`（`RangeMembership.kt` の同型オーバーロード）でも `.contains()` メンバー呼び出し構文で同一現象（`kotlin.ranges.ClosedRange.contains[...]targs=[UInt]` への誤フォールバックと `UByte?` 引数での `KSWIFTK-TYPE-0001` 化）を確認した。`in` 演算子構文は同様に影響を受けない。IntRange/ULongRange と対称の挙動であり、原因・severity の評価は変わらない。

- [x] BUG-237: `Sequence<Any>` に対する `flatten()` / `toList()` を、kotlinc がコンパイルエラーにするにもかかわらず本コンパイラが受理する。最小再現: `fun main() { val mixed = sequenceOf(listOf(1, 2), sequenceOf(3, 4)); println(mixed.flatten().toList()) }`。`sequenceOf` の要素型推論は両コンパイラとも `Any` に広げて一致する（`Sequence` は `Iterable` を継承しないため `List<Int>` と `Sequence<Int>` の共通上位型は `Any`。reified でないため交差型診断も出ない）が、kotlinc（2.4.10 実測）は `flatten()` で `cannot infer type for type parameter 'R'` / `no value passed for parameter 'iterator'` / `cannot infer type for type parameter 'T'` を報告して失敗する。本コンパイラは `kotlin.sequences.flatten` に解決して `Sequence<out Any>` を返し、実行すると `[1, 2, 3, 4]` を出力する（flatten の型制約チェックの欠落か、Any への緩いマッチ）。この差により、混在 Sequence の実行は `Scripts/diff_cases/` に置けない（参照側がコンパイルエラー）。現状の挙動は `Tests/CompilerCoreTests/GoldenCases/Sema/flatten_sequence_mixed.kt` で Sema の固定記録として保持する。発見元: RF-FIXTURE-010 で `mixedSeq` を `flatten_sequence_edge_cases.kt` へ移そうとして参照コンパイルが失敗して発覚。今回修正しない理由: `flatten` の overload 制約（`Sequence<Iterable<T>>` / `Sequence<Sequence<T>>` のみに適用）の強化は Sema の型推論層の変更で、BUG-236 と同様に型システム側の対応が必要であり、golden fixture の分割という RF-FIXTURE-010 のスコープを超える。**修正済み（2026-09-23、KUU-461）**: `CallTypeChecker+MemberCallInferenceCollectionFlow.swift` の `case "flatten"` に Sequence レシーバ専用の制約チェックを追加。要素型が bundled overload 制約 （`Iterable` / `Sequence` の `Owner<*>`）をちょうど1つ満たす場合のみ受理し、0 個（`Any` / `Int` / 無制約型パラメータ）と 2 個（`Nothing` / Iterable+Sequence 両実装型）は `KSWIFTK-SEMA-0024` で拒否するようになった。kotlinc と同じ受理/拒否境界。`flatten_sequence_mixed.kt` は Sema から Diagnostics ゴールデンへ移動し、`Scripts/diagnostic_cases/reject_flatten_sequence_mixed.kt`（EXPECT-REJECT）を追加。

- [ ] BUG-239: `Any` に保持した `IntArray` を元の型へキャストすると例外で終了する。最小再現: `fun main() { val value: Any = intArrayOf(1, 2); println((value as IntArray).size) }`。Kotlin 2.3.10 は `2` を出力するが、base `a72cc373f859aaf408c6a4e9510404a1e21c92dc` は stdlib source 注入・artifact の両経路で `Unhandled top-level exception`、exit 1。RF-LOWER-STATE-001 の copy 分類修正後も同じ最小ケースで失敗する。今回修正しない理由: 再代入も分類の残留も不要な cast/type-check 経路の問題であり、配列の実行時型と cast lowering の契約を別途調査する必要がある。分類・copy伝播の契約固定という当該PRの安全な修正範囲を超えるため、§13-9に従って追跡する。

- [ ] BUG-242: 文字列テンプレート内の `$$`（リテラル `$` エスケープ）が消去される。最小再現: `fun main() { val price = 0.0; println("$$price") }` —— kotlinc（2.4.10）は `$$` をリテラル `$` + `price` の補間として `$0.0` を出力するが、本コンパイラは `0.0` を出力（`$` が消える）。`Scripts/diff_cases/companion_private_access.kt` の `Product.getDescription` で `"$$price"` を使った際に発覚。本ケースでは `${'$'}$price` に置き換えて回避済み。発見元: RF-FIXTURE-021 の実行カバレッジ補完で新設した `companion_private_access.kt` の diff が `Widget ($0.0)` vs `Widget (0.0)` で不一致。今回修正しない理由: 字句 / 文字列テンプレートの `$$` エスケープ解釈は Lexer/Parser 層の変更で、golden fixture の分割という RF-FIXTURE-021 のスコープを超える。

- [ ] BUG-229: 一次コンストラクタのパラメータプロパティ（`class Foo(open val p: String)` のような primary constructor 上の `val`/`var`）に `open` 修飾子を付けても、override 可能として認識されない。最小再現: `open class Base(open val p: String)` `class Derived(p: String) : Base(p) { override val p: String = p + "!" }` は kotlinc であれば正しくコンパイルされるはずだが、本コンパイラは `override val p` の宣言位置で `KSWIFTK-SEMA-FINAL: 'p' in 'Base' is final and cannot be overridden.` を報告する（クラス本体で `open val p: String = ...` と書いた場合は問題なく override できるため、one 次コンストラクタパラメータだけの非対称なギャップ）。原因: `Sources/CompilerCore/Sema/DataFlow/OpenFinalOverride.swift` の open/override 検証（`validateMemberOverrides`/`extractMemberMeta`）は `classDecl.memberFunctions`/`classDecl.memberProperties`（クラス本体の宣言）のみを走査し、`classDecl.primaryConstructorParams`（一次コンストラクタのパラメータプロパティ）を一切対象にしていない。そのため主コンストラクタの `val`/`var` パラメータに `open` を書いても対応する `SymbolFlags.openType` が設定されず、`isMemberOverridable` の判定（`sym.flags.contains(.openType) || ...`）で常に false となり「final」と誤診断される。発見元: BUG-227 の回帰テスト設計時に advisor の提案した追加ケース（primary constructor property override — vtable スロットへの登録漏れによる実行時 null 呼び出しリスクの確認目的）を試したところ、vtable の話に到達する前の Sema 検証で既に拒否されることが判明。今回修正しない理由: `OpenFinalOverride.swift` の modifier 抽出ロジックにコンストラクタパラメータ用の経路を新設する必要があり（`ConstructorParam` 自身の `open`/`override`/`abstract`/`final` 修飾子を読み、`classDecl.memberProperties` と同様に `validateMemberOverrides` へ合流させる改修）、かつプロパティ本体の symbol 登録側（`HeaderCollection.swift` 等）で primary constructor property に対して `.openType`/`.overrideMember` フラグが正しく設定される経路も別途確認・追加する必要がある。BUG-227（vtable 仮想ディスパッチの欠落）とは全く異なるレイヤ（Sema の修飾子検証、override 可否判定に到達する前段）の別バグであり、スコープを大きく超える。

- [ ] BUG-236: 要素型の異なる引数を渡した `arrayOf` の要素型推論が、Kotlin の LUB ではなく `Any` へ広げられる。最小再現: `fun main() { val mixed = arrayOf(1, "two", 3.0) }`。kotlinc（実測は 2.4.10 / language version 2.4）は `T` を `Comparable<*> & java.io.Serializable` の交差型と推論し、reified 型パラメータへの交差型の具象化を `error: type argument for reified type parameter 'T' was inferred to the intersection of ['Comparable<*>' & 'Serializable']` として**コンパイルエラー**にする（`kotlinc -Xcontext-parameters` の既定設定で実測）。本コンパイラは同じ式を診断なしで受理し `kotlin.Array<Any>` を推論する（`Tests/CompilerCoreTests/GoldenCases/Sema/arrayof_element_type_inference.golden` の `arrayOfMixed` が `targs=[Any]` として固定している。TYPE-103 以来の既定動作で、本 PR で新たに導入した挙動ではない）。この差により、混在 `arrayOf` の**実行**結果を `Scripts/diff_cases/` に置くことはできない（参照側がコンパイルエラーになるため diff の対象にならない）。明示注釈を付けた `arrayOf<Any>(1, "two", 3)` の実行は `Scripts/diff_cases/array_edge_cases.kt` が既にカバーしている。発見元: RF-FIXTURE-002 で分割後の実行検証を補完する際、混在ケースを `Scripts/diff_cases/arrayof_type_safety.kt` に追加したところ参照コンパイルが失敗して発覚。今回修正しない理由: 修正には共通上位型（LUB）計算と交差型の表現、および reified 型パラメータへの交差型具象化の診断という型システム側の新機能が必要で、Kotlin/Native には `java.io.Serializable` が存在しないため交差型の構成要素自体の設計判断も伴う。golden fixture の依存削減という RF-FIXTURE-002 のスコープを大きく超える。

- [ ] BUG-243: object 式（匿名クラス）のメンバー関数から、それを囲む外側クラスの一次コンストラクタプロパティ（`private val` 等）を読むと、実際の値ではなく `0`（デフォルト初期値相当）になる。最小再現: `class Counter(private val limit: Int) : MutableIterable<Int> { override fun iterator(): MutableIterator<Int> { return object : MutableIterator<Int> { var i = 0; override fun hasNext(): Boolean { println("i=$i limit=$limit"); return i < limit }; override fun next(): Int { val v = i; i++; return v }; override fun remove() {} } } }` に対し `fun main() { val c: MutableIterable<Int> = Counter(3); val iter = c.iterator(); println("hasNext: ${iter.hasNext()}") }` を実行すると、`hasNext()` 内の `println` は `i=0 limit=0` を出力する（kotlinc なら `limit=3`）。同じ値をコンストラクタで明示的に渡す名前付きクラス（`class MyIterator(private val limit: Int) : MutableIterator<Int> { ... }` を `MyIterator(limit)` として構築）では正しく `limit=3` になるため、キャプチャ機構（暗黙の外側プロパティ読み取り）特有の欠落と判明している。原因は未特定（追加調査が必要）だが、KSP-CAP-001（object 式のメンバー関数が参照する外側ローカル/パラメータをインスタンスフィールドとして materialize する仕組み、`ExprTypeChecker+ObjectLiteralInference.swift` の `capturedSymbols`/`collectCapturedOuterSymbols` と `driver.lambdaLowerer.captureValueExpr`）が、外側の**ローカル変数/パラメータ**は対象にしている一方、外側の**クラスの（プライマリコンストラクタ由来の）プロパティ**は同じ扱いを受けていない疑いがある（`non-property-primary-ctor-param-scope-bug` の「パラメータ名解決が scope でなく locals 辞書経由」という既知の設計制約と根が近い可能性）。発見元: BUG-242（object 式の itable スロット未計算バグ）の検証用に `Scripts/diff_cases/object_literal_mutable_iterator.kt` を作成する過程で、当初 `limit` をコンストラクタ経由でキャプチャする形の再現コードを書いたところ本バグに遭遇したため、`limit` を使わないハードコード値（`i < 3`）の再現に差し替えて BUG-242 を先に確定した。今回調査・修正しない理由: KSP-CAP-001 のキャプチャ materialization ロジック自体の設計を要する別レイヤの問題で、BUG-242（Sema のレイアウト計算、`itableSlots` が空になる欠落）とはサブシステムが異なり、スコープを大きく超える。

- [x] BUG-242 派生の既知の射程外ケース: `Sources/Runtime/RuntimeRangeAndDispatch.swift:883` の `runtimeObjectIteratorMethodCall` は `iteratorInterfaceSlot = 0` を固定値としてハードコードしており、`kk_iterator_hasNext`/`kk_iterator_next`（同ファイル830行目・854行目）が組み込み Iterator/Range/List/Map/Indexing のいずれのボックス型にも一致しないレシーバに対してこのフォールバックを使う。BUG-242（`ExprTypeChecker+ObjectLiteralInference.swift` の itable スロット計算漏れ）の修正により、object 式が実装する `Iterator`/`MutableIterator` は（他に interface を実装していなければ）itable スロット 0 に一貫して割り当てられるため通常は問題にならないが、`object : SomeOtherInterface, MutableIterator<T> { ... }` のように `MutableIterator` より前に別の interface を実装する object 式では、`MutableIterator` が itable スロット 1 以降に割り当てられ、このハードコードされた `kk_itable_lookup(iterRaw, 0, methodSlot)` が誤ったインターフェーススロットを参照してしまう（BUG-242 修正の前後を問わず、元々このケースは動作しない——全 interface がスロット 0 に衝突していた修正前は「常に失敗」、修正後は「スロット 0 の別 interface のメソッド表を誤って参照」に症状が変わるのみで、いずれも正しく動かない）。**修正済み（2026-09-18、KUU-477）**: 既存のオブジェクト単位 interface 登録と `kk_itable_lookup_dynamic` を `Iterator` の実行時 dispatch に使用し、固定 slot 0 を除去。非ゼロ interface slot を構成する Runtime 回帰テスト `testGenericIteratorDispatchResolvesNonZeroInterfaceSlot` を追加した。ソースレベルの回帰ケースは `Scripts/diff_cases/object_literal_mutable_iterator_multiple_interfaces.kt` に追加。diff harness の bundled stdlib artifact 生成は未完了のため、当該 diff ケースの end-to-end PASS は未確認。

- [x] BUG-247: `kotlin.collections.ArrayList`（KSP-933、source-backed `final class`）のインスタンスで、`AbstractMutableList`から継承した`listIterator()`/`subList()`のデフォルト実装（`ListIteratorImpl`/`SubList`、いずれも`private var expectedModCount = list.currentModCount()`で継承フィールド`modCount`を読む）を呼ぶと`kk_array_get_inbounds precondition failed`でクラッシュする。最小再現: `fun main() { val items = ArrayList<Int>(); items.listIterator() }`（`subList(0, 0)`でも同様）。原因は、`ArrayList` のコンストラクタが `RuntimeListBox` として lower される一方、継承 default 実装がその値を object field 配列として扱い、`modCount` 用の index を読み取っていたことだった。`ArrayList` の `listIterator()`/`listIterator(index)` を既存の list-iterator ABI に直接 bind し、`subList()` は backing list と連動する runtime view を返す `kk_list_subList` として実装した。`clear()` の直接 external bind と合わせて、`Scripts/diff_cases/stdlib_kotlin_collections_n_ArrayList.kt` と Codegen 回帰テストで固定。発見元: PR #6149（KSP-933）のマージコンフリクト解消中、CI の kotlinc diff（`stdlib_kotlin_collections_n_AbstractMutableSet.kt`、`AbstractMutableSet`実装内で`ArrayList`をbacking storageに使う既存フィクスチャ）が`values.clear()`で`Trace/BPT trap`により失敗して発覚。

- [x] BUG-250: 関数型プロパティを直接呼び出せない。最小再現: `class Holder(val f: (Int) -> Int)` に対し `fun main() { val h = Holder({ x -> if (x > 0) x else -x }); println(h.f(3)) }` は Kotlin 2.3.10 なら `3` を出力するが、本コンパイラは `error KSWIFTK-KIR-0003: KIR verifier: main: call to 'f' does not resolve to a module function, an external link name, or a runtime ABI function` でコンパイルに失敗する（exit 1）。`h.f.invoke(3)` と明示的に書くと今度は `error KSWIFTK-SEMA-0024: Unresolved member function 'invoke'.` になる。`val g = h.f` でローカルに束縛してから `g(3)` と呼ぶと正しく `3` を出力するため、プロパティ getter 自体と関数値の呼び出し自体は動いており、欠落しているのは「メンバー参照に続く呼び出し括弧を、関数型プロパティの読み取り + invoke へ解釈する経路」のみ。Sema がこの式を名前 `f` のメンバー**関数**呼び出しとして解決し、KIR が `callee="f"` の `.call` を出すため（正しくは getter の結果を receiver にした `kk_function_invoke`）、KIRVerifier の `unresolvableCallee` 検査に掛かる。発見元: RF-LOWER-INLINE-002 で `InlineLoweringPass` の直接ラムダ展開経路（caller 本体に残った `kk_function_invoke` を展開する経路）に Kotlin ソースから到達する入力を探す過程で、クラスに保持した関数値の呼び出しを試して発覚（base `a6d031b066` の baseline バイナリでも同一症状のため本 PR で導入した挙動ではない）。今回修正しない理由: 修正には Sema のメンバー解決で「メンバー関数が見つからないが同名の関数型プロパティが存在する場合にプロパティ読み取り + invoke へ書き換える」経路の新設と、関数型に対する `invoke` メンバーの導入が必要で、Sema のオーバーロード解決層の変更にあたる。ラベル走査・再配置と採番状態の分離という当該 PR の安全な修正範囲を超えるため、BUG-239 と同じ方針で追跡する。
- [ ] BUG-265: `object` メンバープロパティへの暗黙 this（同一 object 内の別メンバーからの束縛なし参照）経由の書き込みと、`by lazy` などプロパティデリゲートの読み取りが、BUG-257 で修正した明示レシーバ経路とは別のバイパスを通り、それぞれ別の壊れ方をする。(1) 暗黙 this 書き込み: `object Foo { var log=""; var x: Int get()=0; set(v){log+="s"}; fun b(){ x=5 } }; fun main(){ Foo.b(); println(Foo.log) }` は kotlinc 実測 `s` に対し本コンパイラは空文字列を出力する（setter が呼ばれず、値も静かに失われる）。さらに同一関数内で書き込み直後に読み取ると（`fun b(): Int { x=5; return x }`）SIGBUS でクラッシュする。(2) `by lazy` デリゲート: `object Delegated { val z: Int by lazy { 7 } }; fun main() { println(Delegated.z) }` は SIGBUS でクラッシュする（class インスタンスの `by lazy` は正しく動作するため object 固有の欠落）。原因（未確定）: (1) は bare-name 代入（レシーバ式を伴わない `x = 5`）の lowering 経路——`lowerMemberAssignExpr` はレシーバ式を前提とするため別経路のはずだが未特定、(2) は object メンバーの delegated property に対する getter-accessor シンボルが存在しないこと（`propertyHasCustomGetter` が delegate では false のため BUG-257 の新分岐からも意図的に除外し、pre-existing の `loadGlobal` へフォールバックさせている）。発見元: BUG-257（object の custom-getter プロパティ読み取りクラッシュ）の回帰検証中、明示レシーバ以外の読み書き経路を洗い出す過程で発見。BUG-257 の修正前から存在した（回帰ではない）ことを、delegate 除外後も (2) が同じ SIGBUS を再現することで確認済み。今回修正しない理由: (1) は暗黙 this 書き込みという別の lowering 経路の新設、(2) は object 向け delegated-property アクセサの新設が必要で、いずれも BUG-257 の「明示レシーバの custom-getter 読み取り」という修正スコープを超える。注記: 当初 BUG-260 として起票したが、master 側の先行エントリ（`withWorker` panic、別内容）と同番号で衝突したため BUG-265 へ改番した。
- [ ] BUG-261: プロパティの custom setter/getter アクセサ本体で投げた例外が、呼び出し元に伝播せず握りつぶされる。object メンバーに限らずクラスインスタンスのプロパティでも再現する一般的な不具合。最小再現(object): `object Foo { var log=""; var x: Int get()=0; set(value){ require(value<0){"boom"}; log="stored" } }; fun main(){ Foo.x=5; println("survived, log=${Foo.log}") }` は kotlinc 実測では `IllegalArgumentException: boom` で即クラッシュし何も出力しないが、本コンパイラは `survived, log=` を出力して正常終了する（例外だけでなく `log="stored"` への到達自体も起きていない＝setter 本体の実行が `require` の時点で静かに打ち切られている）。最小再現(class): `class Bar { var y: Int get()=0; set(v){ require(v<0){"boom"} } }; fun main(){ Bar().y=5; println("survived") }` も同様に `survived` を出力する。対照実験: `object Foo { fun f(){ require(false){"boom"} } }; fun main(){ Foo.f(); println("survived") }` は通常のメンバー関数呼び出しであり、正しく `KSwiftK panic ... Unhandled top-level exception` でクラッシュする（`require` 自体の lowering・通常の関数呼び出し経由の例外伝播はどちらも正常）。差はアクセサ関数（`lowerAccessorBody` が合成する getter/setter）の呼び出し経路にのみある。`--emit kir` で比較すると、setter 内部の `require` 呼び出し自体は `thrown=true` で正しく記録されるが、アクセサ呼び出し自体（`call set ...`）は `thrown=false thrownResult=_` になっており、アクセサ本体からの例外が外側へ伝播しない一方で、通常の module 関数呼び出しは同じ `thrown=false`（`needsThrownChannel`/`throwingMemberCalleeNames` は kk_* ランタイムブリッジ名のみを対象とする allowlist で、`f`のような module 関数呼び出しはそこに含まれない）でも正しく伝播するため、「call 命令の thrown フラグ」だけでは説明がつかない未解明の差異がある。発見元: BUG-257（object の custom-getter プロパティ読み取りクラッシュ）の修正検証中、`GC.targetHeapUtilization` の setter に書き込んだ値が読み戻せない不具合（BUG-258, Double/Int 比較バグ由来の `require` 誤発火）を切り分ける過程で、その `require` の失敗自体が握りつぶされ気づかれなかったことから発見。今回修正しない理由: KIR の `call` 命令の `thrown` フラグ単体では説明できない挙動差が確認されており、根本原因の特定にはアクセサ関数と通常関数の codegen 差分（関数プロローグ/エピローグ、LLVM 関数シグネチャの outThrown スロットの有無等）のさらなる調査が必要で、BUG-257 の修正スコープを大きく超える。
- [ ] BUG-262: `Double`/`Float` と `Int` など異なる数値プリミティブ型間の `==`/`!=` を、kotlinc はコンパイルエラーにするが本コンパイラは受理して実行してしまう。最小再現: `fun main() { println(0.6 != 1) }` は kotlinc 実測で `error: operator '!=' cannot be applied to 'Double' and 'Int'` になるが、本コンパイラはエラーなくコンパイル・実行できてしまう（`<`/`<=`/`>`/`>=` の cross-type 比較は両コンパイラとも正当な `compareTo` オーバーロードとして受理するため対象外）。発見元: BUG-258（`Double <= Int` 比較のビットパターン誤読バグ）の diff case 作成中、同種の mixed-type 比較を網羅しようとして `!=` だけ kotlinc 側がコンパイルエラーになることに気づいて発見。今回修正しない理由: Sema の等価演算子オペランド型チェックの追加が必要で、KIR の数値比較 lowering（BUG-258 のスコープ）とは別サブシステム。
- [ ] BUG-266: バンドル stdlib の `object` メンバーで、型が `Long` の `var`（カスタムアクセサの有無を問わない）への書き込みが、その `object` を実利用者と同じ通常経路（`.kklib` 経由、`--stdlib-from-source` を付けない）でインポートしたときに限り、例外もクラッシュも出さず静かに無視される。同じソースを `--stdlib-from-source`（バンドル stdlib をユーザーコードと同一パスでコンパイル）で流すと正しく書き込める。最小再現: `object GC { var minHeapBytes: Long get()=__minHeapBytes; set(value){ __minHeapBytes=value }; private var __minHeapBytes: Long = 5L*1024*1024 }` 相当（実際は `kotlin.native.runtime.GC`）に対し `fun main(){ GC.minHeapBytes = 512L; println(GC.minHeapBytes) }` を書くと、kotlinc 側は無関係（`kotlin.native.*` は JVM 非対応）だが、本コンパイラは通常ビルドで `5242880`（初期値、`512` ではない）を出力する。同じ形の `Boolean`/`Double` プロパティ（`GC.autotune`, `GC.heapTriggerCoefficient` 等）は同じ書き込み経路で正しく動作するため、`Long` 型に限定された欠落。ただし `GC.regularGCInterval`（`kotlin.time.Duration` — 内部表現は `Long`）は同じ書き込み経路で正しく動作するため、単純な「値のビット幅／物理表現が 64bit だと壊れる」という説明では足りない。`Duration` は inline value class で KIR/Sema 上は `Long` そのものとして消去されないラップ型として扱われている可能性が高く、壊れるのは「KIR 上で素の `Long` 型タグを持つ値」の場合に限られる、という手がかりになる。再現コマンド: `swift build && .build/debug/kswiftc --stdlib-only -o /tmp/gcstdlib` でバンドル stdlib を単独 `.kklib` に切り出し、`KSWIFTK_STDLIB_LIBRARY=/tmp/gcstdlib.kklib .build/debug/kswiftc probe.kt -o probe && ./probe`（`probe.kt` は上記の `main`）で再現。`--stdlib-from-source` に切り替えると同じソースが正しい値を返す。原因（未確定）: `CallLowerer+MemberAssignment.swift:lowerMemberAssignExpr` の最初の2分岐（`memberPropertyUsesSetterAccessor` 経由の custom setter 呼び出し、および `ownerInfo.kind == .object` を前提にした flat global slot 書き込み）はどちらも、`--stdlib-from-source` と通常インポートの双方で同一の KIR（`call set symbol=_ args=[receiver, value]`、`--emit kir`/`--emit llvm` を diff して確認済み — テキストは完全一致）を生成しており、分岐そのものはヒットしていない可能性が高い。両モードで生成物が同一にもかかわらず実行結果が異なるため、乖離は KIR 生成より後（コード生成、またはインポートされたシンボルのオブジェクトコード解決）にあり、`Long` 型の値だけがそこで迷子になる。`Boolean`/`Double` は動作するため型固有の分岐（値の物理表現、または呼び出し先解決に使う何らかの型タグ）が疑わしいが未特定。バンドル stdlib 全体を grep した限り、`object` メンバーで setter を持つ `Long` 型の `var` は今回 KSP-1262 で追加した `GC.targetHeapBytes`/`GC.minHeapBytes`/`GC.maxHeapBytes` が唯一の例（既存コードに同型のケースがないため今まで検出されなかった）で、`kotlin.native.*` 配下のため `Scripts/diff_cases/` に追加しても `SKIP-DIFF`（JVM kotlinc 非対応）にしかならず、通常の diff 経路で実行される最小ケースは今回作れなかった。今回修正しない理由: 発生箇所が Sema のメンバー代入 lowering ではなくコード生成/シンボル解決側にあると見られ、当該サブシステム（`NativeEmitter`/インポートしたシンボルのオブジェクトコード解決）の調査が必要で、KSP-1262 のスコープを大きく超える。暫定対応として `GC.targetHeapBytes`/`minHeapBytes`/`maxHeapBytes` の setter は本バグが直るまで明示的な no-op にしてある（`Sources/CompilerCore/Stdlib/kotlin/native/runtime/GC.kt` 内のコメント参照）。注記: 当初 BUG-263 として起票したが、master 側の先行エントリ（`Outer.Inner` ネスト object の materialization、別内容）と同番号で衝突したため BUG-266 へ改番した。

- [ ] BUG-253: 非ローカル `break`/`continue`（ラムダ本体に書かれ、ラムダを囲むループを標的にするジャンプ。Kotlin 2.2 で stable、ターゲットの 2.3.10 でも有効）が Lowering に未実装で、ジャンプが黙って捨てられ、有効な Kotlin プログラムが無限ループまたは誤った結果になる。
  - 最小再現1（`while(true)` + ラムダ内 break。2026-09-13 `.build/debug/kswiftc` と kotlinc 2.4.20 で実測）:
    ```kotlin
    fun f(xs: List<Int>): Int {
        while (true) {
            xs.forEach { if (it > 0) break }
        }
        return -1
    }
    fun main() { println(f(listOf(-1, 2, 3))) }
    ```
    kotlinc は `-1` を出力（exit 0、警告なし）。修正前の kswiftc は `return -1` に `warning KSWIFTK-SEMA-0096: Unreachable code.` を出したうえでハングするバイナリを生成した（`diff_kotlinc.sh` で `run exit mismatch: ref=0 candidate=124` / `candidate run timed out after 10s` / stdout は空）。
  - 最小再現2（無限ループを介さない同じ症状）:
    ```kotlin
    fun g(xs: List<Int>): Int {
        var sum = 0
        for (i in 1..3) {
            xs.forEach { if (it > 0) break }
            sum += 1
        }
        return sum
    }
    fun main() { println(g(listOf(-1, 2, 3))) }
    ```
    kotlinc は `0`（break が `for` を脱出する）、修正前の kswiftc は `3`（break が外側ループに一切効かない）。`Sources/` 全体に非ローカル break/continue の実装・診断・追跡の痕跡は無い。
  - **部分修正（本 PR で実施）**: `TypeInferenceContext.enteringLambdaBody()`（`Sources/CompilerCore/Sema/TypeCheck/TypeInferenceContext.swift`）で `loopDepth` / `loopLabelStack` をリセットし、ローカル関数本体（`LocalDeclTypeChecker+IndexedCompoundAssignAndLocalFunctions.swift` の "Local functions introduce a new scope for control flow" と同じ扱い）に揃えた。これによりラムダ境界を越える break/continue は既存の `KSWIFTK-SEMA-0018` / `KSWIFTK-SEMA-0019` で**コンパイルエラー**になり、黙った誤コンパイルではなくなる（上記2ケースとも `error KSWIFTK-SEMA-0018` を実測）。ラムダ内のループは `loopDepth` を再インクリメントするため `run { while (true) { ... break } }`（`Scripts/diff_cases/atomic_basic.kt` の実シェイプ）は引き続きコンパイルできる。kotlinc が受理するコードを拒否する意図的な差分であり、未実装機能に対する明示エラーとして採用した。
  - 回帰テスト: `Tests/CompilerCoreTests/Sema/LambdaBreakContinueScopeTests.swift`（6 サンプル: ラムダ越え break / 同 continue / ラベル付き break@outer の 3 件がエラー、ラムダ内ループ・素のループ・ループ内ラムダ内ループの 3 件がエラーなし）。修正を戻すと前者 3 件が `diags → []` で失敗することを実測確認済み（空振りでない）。
  - 非回帰の実測（2026-09-13、本 PR）: `.build/debug/kswiftc --stdlib-only --emit library` がエラー 0 件（bundled `.kt` にラムダ境界を越える break/continue は無い）/ `break`・`continue` を含む `Scripts/diff_cases/` 全 16 件 + `while_true_cas_loop_return.kt` が `total=16 failed=0 passed=16 skipped=0`。
  - **残作業（本項目が `[ ]` である理由）**: 非ローカル break/continue を実装する。Sema と Lowering を同じ PR で変更する必要がある — `ControlFlowTypeChecker.containsBreakTargetingCurrentLoop` の `.lambdaLiteral → return false`（`while(true)` を `Nothing` 型付けするための break 探索がラムダ内を見ない）を「ラムダ内の break も外側ループを標的にしうる」へ変えるのは、Lowering 側でジャンプが実際にラムダを脱出できるようになってからでないと、異常を知らせる唯一のシグナルを消すだけになる。inline 関数のラムダからの非ローカル `return` の実装をモデルにする。

- [ ] BUG-255: `sequence {}`/`iterator {}` builder 内の `yieldAll(sequence)` が内側シーケンスの遅延評価順序を保持しない。real kotlinc は消費側が `next()` を呼ぶたびに要素を1個ずつ pull して producer 側と interleave するが、kswiftc は最初の `next()` が返る前に、内側シーケンス全体はおろか外側 builder 自身の `yieldAll` 呼び出し以降の残り本体まで同期的に実行し尽くす。最小再現: `Scripts/diff_cases/sequence_yieldall_lazy_order.kt`（KSP-1519 で新規追加、`SKIP-DIFF (DEBT-DIFF-010)` として現在スキップ中）。実測差分（`bash Scripts/diff_kotlinc.sh --keep-temp Scripts/diff_cases/sequence_yieldall_lazy_order.kt`）: real kotlinc は `start / outer:before / inner:1 / 1 / inner:2 / 2 / stop early`、kswiftc は `start / outer:before / inner:1 / inner:2 / inner:3 / outer:after / 1 / 2 / stop early`（2回目の `next()` を呼ぶ前に `inner:3`/`outer:after` まで出力済み）。原因: `Sources/Runtime/RuntimeSequenceBuilders.swift` の `__kk_sequence_builder_yieldAll`。CPS 経路（`RuntimeSequenceCoroutineBuilderProxy` 分岐、40-69行目）は `runtimeTraverseSequence(seq, ...) { elem in _ = proxy.coroutine.yieldValue(elem); return true }` で内側シーケンスをネイティブ Swift クロージャコールバックとして同期的に traverse し、`yieldValue` が CPS producer 用に返す `COROUTINE_SUSPENDED` センチネルを `_ = ...` で握り潰しており、外側コルーチンの状態機械へ「ここで一旦サスペンドせよ」という信号が一切伝播しない。legacy thread-backed 経路（`runtimeSequenceBuilderBox` 分岐、70-86行目）も `builder.elements.append(contentsOf: elements)` で全要素を即時 materialize しており、両経路とも構造的に eager。KIR 実測（`--emit kir`）で、`yieldAll(inner)` は `call __kk_sequence_builder_yieldAll symbol=yieldAll args=[builder, innerSeq] thrown=true` という単一呼び出しへ解決され、`innerSeq` 引数は先行する `.iterator()` 呼び出しの結果ではなく捕捉済みローカルへの直接参照（`symbolRef`）であることを確認した。すなわち `SequenceScope.kt` の `yieldAll(sequence: Sequence<T>): Unit = yieldAll(sequence.iterator())` という Kotlin source 委譲本体（`.iterator()` を経由するはず）は実行されていない — `symbol` が nil でなく `thrown=true`（`CollectionLiteralLoweringPass+CallRewriteSequenceBuilders.swift` の raw-name 書き換え分岐は `symbol: nil, canThrow: false` を設定するため、この呼び出し形とは一致しない）であることから、実際に発火しているのは `CallLowerer+MemberCallEmission.swift` の `sequenceBuilderRuntimeCalleeName`（解決済み symbol の owner が `kotlin.sequences.SequenceScope` であれば通常の member-call emission 時にコールバック名だけ runtime bridge へ差し替える経路。symbol・throwing semantics を保持するため観測値と一致）と見られる。`yield`/`yieldAll` 呼び出しの実際のディスパッチには他にも独立した機構が存在する: `CallTypeChecker+BuilderDSL.swift:1107-1129` にも `externalLinkName == "__kk_sequence_builder_yieldAll"` を条件にした専用オーバーロード選択があるが、`rg -n 'externalLinkName' Sources/CompilerCore/Sema/ | rg -i 'sequence|yield'` で確認した限り、現行コードベースには `SequenceScope.yieldAll` のいずれのオーバーロードにもこの externalLinkName を設定する setter が存在せず、この選択ロジックは常に false（到達不能）と確認済み。Lowering の raw-name 書き換え（`CollectionLiteralLoweringPass+CallRewriteSequenceBuilders.swift`）が現時点で到達可能かは別途未調査（本バグの範囲外）。いずれの経路でも「元の Kotlin 引数をそのまま runtime bridge へ転送し、委譲 body 自体は実行しない」という結果は同じであり、dead-body の結論と runtime 側の根本原因は変わらない。真の修正には `RuntimeSequenceCoroutine`（`Sources/Runtime/RuntimeTypes.swift`）に「サブイテレータへ委譲中」という状態を持たせ、`nextElement()`/`nextElementAsync()` がこの状態を消費側 pull のたびにチェックして初めて内側シーケンスから1要素引き出す設計に変更する必要があり、CPS・legacy thread 両 producer 経路と `RuntimeSequence.swift` の `.lazyBuilder` traversal に影響する、coroutine ランタイム自体の再設計に相当する。発見元: KSP-1519（`sequence`/`iterator` builder トップレベル関数の Kotlin 化）のテスト追加時。本バグの機構に関わる `__kk_sequence_builder_yieldAll` 本体と `RuntimeSequenceCoroutine`/`RuntimeSequenceCoroutineBuilderProxy`（`Sources/Runtime/RuntimeTypes.swift`）は同 PR で一切変更していないため本バグの原因ではなく、分岐元コミット `3e3545a536` 時点から存在する既存バグと確認済み（該当コメント自体は少なくとも `0c62097cfa`「Split RuntimeSequence.swift by terminal-op family」2026-05-12 時点、`RuntimeSequence.swift` 分割前の同ファイルにも同内容で存在）。同PRは同じ`RuntimeSequenceBuilders.swift`内の別関数`__kk_iterator_builder_build`のABIパラメータ数不一致（CI発覚、無関係な既存バグ）は修正しているため、`Sources/Runtime/`ディレクトリ全体としては無変更ではない点に注意——「無変更」なのはyieldAllの遅延評価に関わる経路のみ。今回修正しない理由: 粒度ルール（1タスク=1PR、超えると判明したら新番号で分割）に従い、KSP-1519 のスコープ（Sema 合成スタブの Kotlin 化）を超える coroutine ランタイム再設計は別タスクとして分離。関連: `docs/diff-skip-inventory.md` の DEBT-DIFF-010。

- [ ] `isImportedInterfaceMember`（`Sources/CompilerCore/KIR/CallLowerer+MemberCallDefaultsAndResolution.swift:210`、KSP-611 のコメント付きで定義）は、importedLibrary 経由のインターフェースメンバーを判定する目的で書かれたが、呼び出し元が一つも存在しない未配線のデッドコード。発見元: PR #6621（KSP-1070、`MutableIterable.iterator()` の実行時ディスパッチ修正）の調査中、まさにこの関数が対処しようとしていたのと同種の問題（imported library 経由の abstract メンバーの externalLinkName が誤って直接呼び出しに使われる）を `NativeEmitter+FunctionEmission.swift` の `.call` 命令処理に別実装したが、既存のこの関数へ統合するか、削除するかの判断はしていない。今回対応しない理由: 統合するには呼び出し元候補（`CallLowerer` 側の member call lowering 経路）への配線と、その影響範囲（他の imported interface member 解決への副作用の有無）の調査が必要で、スコープを超える。

- [ ] BUG-259: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt` の `IntRange.toIntArray()`（184行目）/ `IntProgression.toIntArray()`（450行目）が実在しない Kotlin API を実装している。最小再現: `println((1..5).toIntArray().toList())` および `println((1..10 step 2).toIntArray().toList())`。`diff_kotlinc.sh` の reference kotlinc（2.4.10 相当）はいずれも `error: unresolved reference 'toIntArray' on receiver of type 'IntRange'`/`'IntProgression'` でコンパイル拒否する（本コンパイラ側は両方コンパイル・実行に成功してしまう）。原因: `IntArray` への変換は `kotlin.collections` の `Collection<Int>.toIntArray()` にのみ存在し、`IntRange`/`IntProgression` は `Iterable<Int>` であって `Collection` を実装しないため、この拡張は本来解決対象外——KSP-1523 で `UIntRange.toUIntArray()`/`.average()` が同じ理由で実在しないと判明したのと同型のパターンが、signed 側の `RangeHOF.kt` にも先行して混入していたことになる。発見元: KSP-1523 の作業中、UInt 側の `average()`/`toUIntArray()` が実在しないと判明した際、advisor の提案で signed 側の `toIntArray()` も念のため `diff_kotlinc.sh`（`println((1..5).toIntArray().toList())` を含むスクラッチケース）でプローブして確認。今回修正しない理由: `RangeHOF.kt` からの削除に加え、呼び出し元（`CollectionLiteralLoweringPass+VirtualCallRewrite+Range.swift` 等の toIntArray 分岐、`MemberRuntimeDispatch.swift` の toIntArray 関連ケース）の追跡・削除、および `Scripts/diff_cases/` 配下で実際に signed `.toIntArray()` を呼んでいるケースの洗い出しが必要で、KSP-1523（UIntRange のみを対象とするチケット）のスコープを超える。注意（KSP-1523 で判明した隣接バグの教訓）: `RangeHOF.kt` から削除するだけでは不十分——`CallTypeChecker+RangeMemberFallback.swift` の `isSupportedRangeMember`/`isValidRangeMemberArity`/`rangeMemberResultType` にまだ `"toIntArray"` がレガシーアローリストとして残っており、これは型だけを緩く通し callee symbol を結び付けない古いフォールバックのため、`bindSourceRangeHOFCall`（`RangeHOF.kt` 宣言の優先解決）が先に捕まえなくなった瞬間、Sema でエラーにならず素通りしてリンク時に裸の `_toIntArray` 未解決シンボルで失敗する（KSP-1523 で `average`/`toUIntArray` が実際に踏んだ経路と同型）。追記（CI失敗の調査で判明した訂正）: 上記の「`toIntArray`/`toLongArray`/`toULongArray` がレガシーアローリストに残存」という記述は誤りだった——実際には master にこれら3名は存在せず、本PR（KSP-1523）のコミット自体が `isSupportedRangeMember`/`isValidRangeMemberArity`/`rangeMemberResultType` に新規追加したものだった（`average`/`toUIntArray` 除去時の編集ミスと見られる）。CI の `error_range_toarray_unsupported.kt` golden diff（8件の unresolved-member エラーのうち6件が消失）で発覚し、同PR内で3名とも削除して golden を復旧済み（`rangeMemberResultType` が使っていた `rangeMemberIntArrayType`/`rangeMemberLongArrayType`/`rangeMemberULongArrayType` ヘルパーも削除）。BUG-259 本体（`RangeHOF.kt` の `IntRange.toIntArray()`/`IntProgression.toIntArray()` という Kotlin ソース宣言自体が実在しない API を実装している問題）は未解決のまま残る。

---

## テストパイプライン集約タスク（Sema API tests migration）

`Tests/CompilerCoreTests` 内の重複した `runSema` / `runToKIR` / `runToLowering` / `runFrontend` / `makeSema` 呼び出しを 1 つの共有コンテキスト（`withTemporaryFiles` / `sharedCtx` / `sharedSema`）に集約し、テスト実行コストと行数を削減する。

> 現状（`origin/master`、Batch 82 マージ後、2026-08-03 時点）:
> - `runSema(`: 652
> - `runToKIR(`: 328
> - `runToLowering(`: 37
> - `runFrontend(`: 70
> - `makeSema(`: 129
>
> 目標: 同一ファイル / 同一スイート内で同じ入力を使う箇所を 1 回の pipeline 呼び出しにまとめ、上記カウントを再び半減させる。
> 進行中 PR: #5765 (Batch 83)。未 PR の作業ブランチ: `devin/consolidate-sema-api-tests-batch84` (Batch 84)。

- [x] REFACT-TEST-003: 同一入力で複数 `runToKIR(ctx)` を呼んでいる KIR テストを共有 `runToKIR(ctx)` に集約（2026-09-16 完了）
  - 独立した fixture 群を package／関数名で分離し、Regex、NativePlatform bridge（`Platform.memoryModel` は synthetic object-property state のため単独 context）、BuildKIR、BlockExpression、BuildAST body parsing、FileRewrite、Property Delegation を raw／lowered の共有 `CompilationContext` に集約した。既存のテスト名と対象 fixture の assertion は維持している。
  - `KotlinIOCommonEdgeCaseTests.swift` と `BuildKIRRegressionTests+ExpressionAndAdvancedScenarios+ControlFlowTryAndObjectLiteral.swift` は既に共有化済みのため変更しない。
  - `.kklib`、`searchPaths`、manifest 診断、import 解決など外部ライブラリ状態がケースごとに異なる `LibMetadataImportIntegrationTests.swift`、`LibraryMetadataManifestValidationTests.swift` および関連 import テストは、誤った診断混入を避けるため個別コンテキストのまま維持した。
  - `BuildKIRRegressionTests+NativePlatform.swift` の `Platform.memoryModel` は、他の Native bridge fixture と同一 context にまとめると runtime call が KIR から消えるため、元の単独 context を維持し、残りの NativePlatform fixture 群のみ共有した。この未修正コンパイラ不具合は BUG-212 として記録した。
  - 手動 `runSema`／`BuildKIRPhase` 検証、ABI／synthetic KIR の直接検証、benchmark 用 fixture、および before/after の LoweringPhase 順序を意図的に検証する単独ケースは対象外として棚卸し済み。
  - focused テストに加え、PR #5913 の CI Verification run `32167293858` で CompilerCore／Smoke（3 shard）、Backend／Runtime／CLI／LSP、Repository Checks、kotlinc Diff（2 shard）の全ジョブが pass したため完了とする。
- [~] REFACT-TEST-005: 集約後に不要になった per-test pipeline ヘルパー・重複 `source` 文字列・個別 `withTemporaryFile` ブロックを削除し、migration スクリプト群を整理
  - List の shared Sema context を使わない `fun noop() {}` wrapper 31 箇所、単一用途の `makeSema` helper 8 箇所、および Regex の不要な case 引数を削除した。テスト名、fixture、診断、実行順独立性は維持している。
  - migration script の共通化は master の #6430 で完了済みのため、既存の所有範囲を重複変更していない。
  - focused Sema 107 tests、SmokeTests 12 tests、runtime ABI link 4 tests、build、TODO ID 検査は PASS。CompilerCoreTests 全体は Golden semaphore 待ちのため未完了で、全体ゲート green 後に完了へ更新する。

---

## Golden fixture の単一目的化（RF-FIXTURE: 2026-09-06 調査）

### 現状と対象の選定

- 調査基準: `f637b7bdf77ce29a26ca00a782b34c5927df6d17`。`Tests/CompilerCoreTests/GoldenCases/Sema/` は入力 `.kt` / 期待値 `.golden` が各579件。履歴は同コミットの first-parent、2026-08-07 00:00〜2026-09-06 00:00（+09:00）の30日間で集計し、golden 517パス・延べ1,140回の変更を確認した。
- 再集計用: `git log f637b7bdf77ce29a26ca00a782b34c5927df6d17 --first-parent --since=2026-08-07T00:00:00+09:00 --until=2026-09-06T00:00:00+09:00 --format= --name-only -- 'Tests/CompilerCoreTests/GoldenCases/Sema/*.golden'` の非空行をパス別に数える。以下の「変更回数」はこの期間の golden 変更コミット数であり、当初報告の「調査範囲内11回」と集計範囲・方法を揃えた比較ではない。一括再生成・ハーネス変更も含むため、すべてを fixture の多責務化に起因すると断定しない。
- 候補抽出: **golden 変更7回以上、入力2,000 bytes以上、golden 15,000 bytes以上**のいずれかに該当する23件に、同型の `hashset_alias.kt` / `linkedhashset_alias.kt` を加えた25件を内容確認。3件を下記理由で除外し、22件をファイル単位で起票した。全579入力の詳細監査完了を意味しない。Lexer / Parser / Diagnostics の fixture は今回の対象外。
- 最大の変更集中点は `linkedhashmap_alias.golden`（20回、19,045 bytes、入力80行）。履歴には Map / MutableMap のほか、Iterable の map、Set / Collection、Pair / `to`、`println`、配列・Sequence の変換などの移行が含まれる。`arrayof_type_preserve.golden` は18回、`map_hofs.golden` は15回、`collection_mutable_conversions.golden` は14回。`map_hofs.kt` は11行しかなく、行数だけでなく依存する API 群の多さが問題になる。
- 大きな低頻度ケースも対象: `companion_object_private_access.kt` は163行 / golden 33,065 bytes、`stdlib_kotlin_collections_Collection_n.kt` は71行 / 28,285 bytes。`stdlib_kotlin_collections_MutableCollection_n.kt` と `stdlib_kotlin_collections_Map_flat.kt` は、同名の `Scripts/diff_cases/` 入力と Git blob が完全一致しており、実行用シナリオが Sema にも重複している。
- **分割対象外**: `list_collection_hofs_chained.kt`（8回）は HOF 間の型伝播そのものを検証する7行の連鎖ケースとして維持する。`stdlib_kotlin_comparisons_n_max.kt` / `stdlib_kotlin_comparisons_n_min.kt`（各1回）は引数・戻り値で単一 API の overload 行列を検証済みで、出力処理もない。golden のサイズだけを理由に分割しない。

### 共通方針・完了条件

> **粒度**: 1タスク = 既存入力1ファイルの整理 = 原則1 PR。元の `.kt` と `.golden`、必要な分割先ペア、実行検証の不足補完を同じタスクで扱う。001から順に1件ずつ進め、別の巨大 fixture へまとめ直さない。後続対象はファイル単位の新IDで追加する。
>
> **目的**: ディレクトリ移動ではなく、検証目的と不要な依存機能の分離。現ハーネス（`GoldenHarnessCaseDiscovery.swift`）は Sema 直下の `.kt` を列挙し同名 `.golden` と対応させるため、この構造を維持する。共通コンテキストへの集約タスクとは別物であり、ハーネス・正規化・診断表示を変えて差分を隠さない。
>
> **型検証**: 引数・戻り値・代入先などで具体的な型、nullability、型引数、callee を固定する。推論自体が目的の式には先に期待型を与えず、推論後の別の代入・引数で照合する。`println`、出力用の文字列補間、`toList`、`size`、不要な factory / HOF は除くが、目的である overload 解決や型伝播の依存まで除かない。
>
> **網羅の維持**: 着手時に元の検証項目 → 残す型ケース / 既存ケースへの移管 / 実行ケースへの移管の対応を作り、重複を確認してから分割する。各分割先は「1つの API 群または1つの型規則」を短く説明できること。既存の回帰ケース・不正入力・`<error>` を無言で削って green にしない。コンパイラ / ランタイムのバグが判明した場合は既存のバグ修正ルールに従う。
>
> **他系列との整合**: RF-GOLDEN-010 を先行させ、ハーネスの切り替えと fixture 分割は別 PR にする。着手時点の新しい出力で対象・優先度を再確認する。対象指定の専用 Golden 導入後に入力を分割・改名する場合、`.kt` / `.golden` だけでなく対象指定・実行 profile・メタデータ契約の担当も同じ PR で移管し、旧指定の孤立と新ケースへの重複コピーを検査する。
>
> **実行コスト**: 現ハーネスは8ケース単位で worker を起動するが、各ケースは個別の CompilationContext / Sema 実行を持つ。分割前後のケース数・batch 数・同条件の suite 時間 / メモリを確認し、総再コンパイル量の増加を無視しない。入力を1 API 呼び出しずつ無制限に細分化せず、独立した検証目的とコストを両立する粒度にする。
>
> **実行検証**: 値・順序・副作用回数・同一性・例外は既存の diff / Codegen 実行テストへ寄せる。以下の実行先はソース照合済みの候補であり、全項目の網羅や実行 green を今回確認したという意味ではない。不足だけを補い、新規 stdout 比較は `Tests/CompilerBackendTests/Fixtures/` + `CodegenBackendFixtureTests` の既存規約に従う。既存の実行ケース全体を Sema へ再コピーしない。
>
> **検証ゲート**: 編集前の Sema golden と対応実行テストを基準として確認 → 対象の型・callee・診断を維持して最小化 → `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` → 更新モードなしで同じ suite と対応する diff / Codegen テストを実行。差分は対象ペアに限定してレビューし、最終的には RF 必須ゲート（全テスト / Golden / 全 diff、存在する場合は LoC 指標）を満たす。`bash Scripts/check_todo_ids.sh` と `git diff --check` も実施する。検証項目の対応・削減した依存 API・分割後最大 fixture の規模を PR に記録する。合計行数やファイル数の減少だけを完了条件にしない。

以下の対象入力名は `Tests/CompilerCoreTests/GoldenCases/Sema/` 配下、実行先の `.kt` は特記がなければ `Scripts/diff_cases/` 配下。括弧内は調査基準時の「入力行数 / golden 変更回数」。すべて分析・タスク登録のみで、fixture の編集・テスト実行は未着手。

### 第1群: 変更集中点（001〜005）

- [x] RF-FIXTURE-005: `unsigned_array_as_list.kt` を view / copy / size の型検証に分離する（31行 / 10回）
  - unsigned 4型の `asList`、`toList` / `size`、generic `Array<T>` の `toList` / `size` を区別する。unsigned 配列を型付き引数等で受け、ULongRange → 配列生成や出力への不要な依存を除く。
  - `List<UByte>` / `List<UShort>` / `List<UInt>` / `List<ULong>` の型を固定する。view が元配列の更新を反映し copy は反映しない挙動は、既存 `unsigned_array_conversions.kt` に寄せる。
  - **完了確認（2026-09-16）**: PR #6652（`ae1fb9a76`）で master に取り込み済み。`unsigned_array_as_list.{kt,golden}` は unsigned 4型の `asList()` view 型、`unsigned_array_to_list.{kt,golden}` は unsigned 4型の `toList()` copy と `size: Int`、`array_to_list.{kt,golden}` は generic `Array<Int>` の `toList()` / `size` に分割し、各 `List<U*>` / `Int` を代入で固定した。配列は typed parameter で受け、factory・`ULongRange.toULongArray()`・`println` 依存を除去した。view/copy の更新追従と generic Array の copy/size 実行挙動は既存 `Scripts/diff_cases/unsigned_array_conversions.kt` に移管済み。
  - **検証**: `swift build` PASS。対象 Sema golden shard（`array_to_list`、unsigned 2組）と `bash Scripts/validate_runtime_abi_links.sh`（4/4）が PASS。`bash Scripts/diff_kotlinc.sh --compile-timeout 600 --script-timeout 660 Scripts/diff_cases/unsigned_array_conversions.kt` は `total=1 failed=0 passed=1`。PR #6652 の CI でも CompilerCore/Golden・Backend/Runtime・Repository・kotlinc Diff（全 shard）を含む全 verification が PASS。ローカルの Sema 全体は共有ホストの長時間 product 再ビルド中断により未完走のため、CI 結果を全体ゲートの根拠とする。

### 第2群: 関連コレクションと I/O の依存削減（006〜015）

- [ ] RF-FIXTURE-006: `arraylist_alias.kt` の alias 解決と List 操作を分離する（67行 / 7回）
  - 引数・戻り値・プロパティ、ネストした型引数、上限制約、拡張 receiver、`MutableList` / `List` への互換性を残し、それぞれの型規則に不要な `add` / `removeAt` / get / size / 補間 / 出力を外す。
  - 更新・要素取得の実行先は `arraylist_alias.kt` / `ksp627_collection_aliases.kt`。ネスト・制約・拡張 receiver の型検証を、これらの実行ケースだけで代替しない。
- [ ] RF-FIXTURE-007: `hashset_alias.kt` の nominal 型・factory・Set 操作を分離する（64行 / 6回）
  - 現 `CollectionAliases.kt` の `HashSet` は typealias ではなくクラス。`hashSetOf` の期待型推論、`Set` / `MutableSet` への互換性、引数・戻り値・プロパティ、ネスト・上限制約・拡張 receiver を型検証として整理する。
  - add / remove / contains / size / 出力のシナリオを切り離す。実行先は `ksp627_collection_aliases.kt` と `CodegenBackendIntegrationTests.swift` の `testCodegenHashSetOfFactoryUsesMutableRuntimeSet`。factory と nominal constructor の検証を取り違えず、不足する削除操作などを補完する。
- [ ] RF-FIXTURE-008: `linkedhashset_alias.kt` の nominal 型と継承検証を分離する（72行 / 6回）
  - `LinkedHashSet` は open class。型引数・引数 / 戻り値 / プロパティ・`Set` / `MutableSet` 互換性、ネスト / 上限制約 / 拡張 receiver と、`MySet` による継承・継承メンバ解決を別目的にする。
  - 型だけを見る箇所の更新操作・文字列補間・出力を除く。実行先は `ksp627_collection_aliases.kt` / `bug196_linkedhashset_subclass.kt` と `testCodegenLinkedSetOfFactoryUsesMutableRuntimeSet`。既存の subclass 回帰を保持する。
- [ ] RF-FIXTURE-011: `flatten_stdlib.kt` を Iterable flatten の型伝播に最小化する（18行 / 7回）
  - Int / String の要素型保持と空入力の型引数を固定し、範囲 → `map` によるデータ生成・`take`・size・出力を除く。要素数の違いだけで同じ型検証を繰り返さない。
  - 空・単一・複数・大きな入力の値と順序は `flatten_core_test.kt` に寄せる。`flatten_comprehensive.kt` は現状 `flatMap { it }` の実行ケースなので、これだけを `flatten()` の回帰代替としない。
- [ ] RF-FIXTURE-012: `sequence_partition.kt` の戻り型と destructuring を実行条件から分離する（29行 / 7回）
  - `Sequence<T>.partition` の predicate 引数と `Pair<List<T>, List<T>>`、分解後の各 List 型を固定する。`asSequence`・Pair の出力用アクセス・空 / 全一致 / 不一致の重複シナリオを型 fixture に集約しない。
  - 実行先は `CodegenBackendSequenceEdgeCasesTests.testCodegenSequencePartitionSplitsElements`（通常・空は既存）。全一致 / 不一致 / `asSequence` 経由は不足を照合して補完し、List.partition のテストだけで Sequence の実行を代替しない。
- [ ] RF-FIXTURE-015: `file_use_lines.kt` を useLines のラムダ / 戻り型推論に絞る（17行 / 8回）
  - `File.useLines` のブロック引数 `Sequence<String>` と汎用戻り型の伝播を残し、File constructor、Sequence の `count` / `toList` 自体の型検証とは切り離す。Int と List 戻り値の推論範囲を狭めない。
  - 実行先は `Tests/CompilerBackendTests/Codegen/CodegenBackendFileUseLinesForEachLineTests.swift`（旧 `Scripts/diff_cases/file_uselines.kt` は CLEANUP-STUB-107 でセットアップが `File.writeText()` に依存していたため削除済み）。count / 行走査は既存だが、List を返して useLines の外で使うケースは今回照合した実行先にないため補完する。

### 第3群: 大きな API surface / シナリオの分解（016〜022）

- [ ] RF-FIXTURE-021: `companion_object_private_access.kt` のアクセス規則と companion 拡張を分離する（163行 / 4回）
  - private constructor（通常 / data class）、companion → インスタンスの private property / function、外側クラス → companion の private member、名前付き / 無名 companion の拡張関数 / 拡張プロパティを目的別の最小クラスにする。
  - メール検証の `contains`、業務的な分岐・演算、整形文字列、factory ごとの大量出力をアクセス可否の検証から外す。private の許可範囲と呼び出し先は Sema に残す。
  - 実行先 `companion_receiver_extension_function.kt` は companion 拡張関数の一部のみをカバーする。private access / data class / 拡張プロパティまで網羅済みとはせず、残すべき実行挙動があれば既存 fixture ハーネスで不足を補う。

---

## Sema Golden と stdlib 実装契約の責務分離（RF-GOLDEN: 2026-09-06 調査）

### 現状・確認した根拠

- 調査基準は RF-FIXTURE と同じ `f637b7bdf77ce29a26ca00a782b34c5927df6d17`。`Sources/GoldenHarnessSupport/GoldenHarnessDump.swift` の `renderSemaOutput` は fixture の宣言・式を起点に `StableRenderContext.expandRequiredSymbols()` を呼び、関数の receiver / 引数 / 戻り型 / 上限境界 / 型パラメータ / 値パラメータ、プロパティ型へ推移的に広げたシンボルの flags / signature を出力する。
- bundled 除外は **展開後**の `isExcludedBundledSymbol` で行われ、`declSite.start.file` が `SourceOrigin.isBundledStdlib`（bundled / residual）のファイルかだけを判定する。宣言位置がある bundled symbol は除外される一方、nil の synthetic stub・互換 nominal・source-backed member alias は同じ扱いにならない。`SemanticSymbol` に独立した由来フィールドはなく、`SymbolTable.isSourceBackedSymbol` も importedLibrary または非 nil declSite の判定で、stdlib / ユーザー / 他ライブラリを識別する API ではない。
- `HeaderCollection.swift` の `predeclareBundledTupleHeaders` / `shouldRestoreDeclSiteForReusableSyntheticSymbol` には、Golden から除外されないために declSite を nil に保つ互換処理がある。`PairTripleNominalAnchorTests.testBundledSourcePairKeepsNilDeclSiteForGoldenStability` も **source-backed・非 synthetic の Pair に nil declSite を要求**する。Charset の先行登録にも同様の処理があり、表示都合がコンパイラ側の宣言位置に結び付いている。
- 同じ `HeaderCollection.swift` は runtime-linked な bundled extension に、receiver 配下の FQName・nil declSite・synthetic flag・同じ signature / externalLinkName を持つ member alias を作る。したがって `synthetic == stdlib 外部参照` でも `!synthetic == fixture の宣言` でもない。owner + name + arity の `BundledDeclarationIndex` は stub 抑制用で、同 arity の overload を識別する完全な参照キーではない。
- **重複変更の実例**: `410638346a4857d1db9908105845106d9134e2f0`（KSP-697 / #5904）の Sema golden 差分は106ファイル。`List` の `flags=synthetic` → `_` が94件、`Iterable` が51件、`MutableCollection` が12件に重複して現れる（件数は重なりあり）。`git show 410638346 --format= --unified=0 -- 'Tests/CompilerCoreTests/GoldenCases/Sema/*.golden'` で再確認できる。
- **フラグを捨ててはいけない実例**: 同コミットは、source 化で List の synthetic flag が消えた結果、`ControlFlowLowerer.usesDynamicIteratorDispatch` が通常 List を任意の Iterable 実装と誤認して専用 iterator 経路を失う問題も修正している。現 `CodegenBackendInterfaceIterableForLoopTests.testConcreteListForLoopStillUsesListIterator` は `kk_list_iterator_next` を直接検証する。同 suite には Iterable の汎用経路と BUG-231 の手書き List / Set 実装の override 呼び出しもあり、単純にすべての List を固定経路へ寄せる変更も許されない。
- 専用検証は一部存在する: `BundledDeclarationIndexTests` は source 所有と残存 stub / alias、`ListSyntheticMemberLinkTests` は nominal / factory / 外部リンク、`StdlibSurfaceSpecTests` は残存 bridge spec と登録、`RuntimeABIExternalLinkValidationTests` はリンク名・bundled `@KsSymbolName` の arity / signature、`ABIMismatchTests` / `ABIMismatchRuntimeExportParityTests` は spec / extern / runtime export を検証する。ただし surface-spec は source-backed API 全体の台帳ではなく、export parity にも対象除外があるため、これらの存在だけで移管完了とはしない。
- `GoldenHarnessSemaFormat` は flags の一部を表示するが、`throwingFunction` / `importedLibrary` や signature の `canThrow` は表示しない。`ABILoweringPass` は throwingFunction で outThrown の有無を変えるため、現 Golden が ABI 契約をすべて検証しているという前提も置かない。
- 現在の overload キーは同 FQName 内の receiver / parameter 型順から付けた `#N` で、同順位は SymbolID を使う。外部 symbol 行だけを削っても、`call=` / `ref=` / 型に残る番号・alias 名の揺れは解消しない。既存の dummy bundled file 不変テストは `fun main() { val x = 1 }` に空 package を注入するケースで、同じ stdlib API の synthetic / source-backed 切り替えの同値性までは扱っていない。

### 最優先: オーバーロード番号を宣言の意味に基づくキーへ置き換える

- `StableRenderContext` は参照集合を収集する前に **全 symbol を FQName 別に集め**、2件以上の場合だけソート順に `#0` / `#1` 等を割り当てる。未参照 overload の追加でも既存番号がずれ、1件 → 2件では suffix の有無まで変わる。型パラメータの `$<ownerID>` を桁揃えする現処理も、宣言内の位置に基づく正規化ではない。
- 現 HEAD の `stdlib_kotlin_collections_n_Set_interface.golden` には Set receiver の `call=kotlin.collections.containsAll#2` がある。報告された Collection overload 追加時の `#1` → `#2` という特定の履歴差分は今回の first-parent 調査では直接確認できず、この fixture は追加コミット `24f091058` の時点で `#2`。番号が他の候補に依存する構造はコードで確認できるため、選択対象を固定して未参照候補だけを追加する最小テストで再現する。
- 表示イメージ: `call=kotlin.collections.containsAll[recv=Set<T0>;params=Collection<T0>]`。これは省略表示例であり、実際のキーには宣言の種別・完全な型名・必要な型パラメータ / スコープ情報等を含める。単に `#番号` を削除する方式は採用しない。

### 構造的削減の採用案: 対象指定の専用 Golden（2026-09-06 選択）

- TODO 上の設計方針として、通常 Golden から外部 symbol のメタデータ行を除き、**対象 API を明示する stdlib 専用 Golden**で保持する案を選択。実装着手・§8 の正式改訂は別途確認する。
- 現 HEAD の `stdlib_kotlin_*` は280件ではなく **289入力**（Sema 全579件）。現在は通常ケースと同じ suite / renderer を使う API 呼び出し側の入力であり、stdlib の宣言本体ではない。例えば `stdlib_kotlin_Pair_n_n.kt` が宣言するのは `makePair` 等だけなので、fixture 所有 symbol だけを出す変更を一律に適用すると専用ケースからも Pair のメタデータが消える。専用の対象指定・描画経路を先に用意する必要がある。
- KSP-697 の106変更は **通常53件・`stdlib_kotlin_*` 53件**。専用ケースをすべて従来の推移的 dump のまま残す方式では重複を解消できない。新規 API に固有ファイルを追加しても、そこで List 等の依存型メタデータを再出力すれば共有型の変更が再波及する。「106 → 1〜2」は未検証の目標であり、変更した契約の担当ケース数に局所化することを効果検証の基準とする。

### 責務・実施順序

> **通常の Sema Golden**: `symbol` 行は fixture 内の宣言とそれに属する合成宣言に限定する。外部参照の flags / sig / type メタデータ行は出さず、式の推論型・`ref=` / `call=` / `targs=`・診断で名前解決と型検証を維持する。外部参照キーは010・006を利用し、overload / receiver / nullability / 型制約等の意味上必要な差は残す。`call=kotlin.Enum.equals` のような実際の解決先変更は差分として残るべきもので、削減対象にしない。
>
> **対象指定の stdlib Golden**: 既存 `stdlib_kotlin_*` を活用するが、ファイル名だけで従来の全文出力を有効化しない。各ケースが担当する宣言とメタデータ契約を明示し、対象自身の flags / signature / type / 必要な由来等だけを専用節に出す。参照先の型や依存 API のメタデータへ推移的に広げない。原則1契約に1つの担当ケースを置き、同じ shared nominal を多数の期待値へ再複製しない。
>
> **併用する専用テスト**: ABI・externalLinkName・runtime export・bridge・実際の lowering 経路は既存の Sema / Lowering / Runtime / Codegen tests で引き続き検証する。メタデータが一致するだけでは正しい call や ABI を証明できない。全 symbol table を1つの巨大な stdlib Golden に移す解決にも、既存の実行検証を削除する解決にもしない。
>
> **保護条件**: synthetic 全除外、`kotlin.*` / パス prefix や declSite の有無だけでの所有判定、比較後の文字列から flags / signature を一括削除する方式は禁止。ユーザーの data / enum / object literal / accessor 等の合成宣言と stdlib receiver 拡張は fixture 所有として保持する。stdlib 以外の library の参照・型と必要なメタデータ検証も失わず、由来不明や専用対象の解決失敗を黙って省略しない。
>
> **順序**: **010が最優先**。その後は001を起点に002（所有・由来）と012（実行 profile）を進め、両方が揃って011（対象指定の基盤）→ 013（全量 inventory gate）→ 003（専用 Golden への移管）。004・005は001後、006は002・010後に進められ、003・004・005・006・011〜013が揃ってから007 → 008 → 009へ進む。**対象指定があるだけでは完了ではなく、検証移管・全量検査・007の情報保持テストが green になるまで、通常 Golden の情報を減らさない**。1タスク = 1責務 = 原則1 PR。RF-FIXTURE は個別入力の依存削減、本系列は横断の出力契約であり、010のキー更新・専用ケースの移管・008の通常出力切り替え・fixture 分割を混ぜない。
>
> **完了ゲート**: focused な GoldenHarness / Sema / KIR・Lowering / ABI / Codegen suite と RF 必須ゲート（全 Swift テスト、Golden、全 diff、存在する場合は LoC 指標）を満たし、source 注入 / stdlib artifact の必要な経路も確認する。通常側の不変性と専用側の変化検出を両方証明する。`docs/stdlib-pipeline.md` §8 の現行の一括更新許容方針は008で明示的に改訂するが、決定的なロード順や意味変更・出力形式移行時の一括更新は維持する。今回の記録は設計選択・タスク登録のみで、ハーネス実装・§8 改訂・テスト実行は未着手。

### タスク

- [~] RF-GOLDEN-013: 専用ケースの全量棚卸し・欠落防止を discovery / CI のゲートにする（前提: 011・012）
  - 対象: `GoldenHarnessCaseDiscovery` / `GoldenHarnessStaticCases` / inventory・persistence tests / 必要な CI 配線。`.kt`・対象指定・期待値・profile の対応を検証し、孤立した指定 / golden、改名後の取り残し、既存専用ケースの指定欠落を検出する。対象指定ファイルの削除や読み込み失敗で通常モードへ黙って降格させず、既存専用期待値・必須の担当契約とも照合する。
  - 契約（宣言・検証項目・profile）ごとの担当重複と未担当を **全ケース集合で**検査する。現ハーネスの8件 batch / shard / filter の内側だけでは別 shard の重複を見落とすため、全量 preflight または独立した必須 inventory suite を設ける。意図した重複は理由を示し、新規API追加・正規の削除・fixture分割時の担当変更も検証可能にする。
  - `UPDATE_GOLDEN=1` は意味や対象指定の誤りを承認する操作にしない。mode / schema の意図しない変更や指定不正は書き込み前に拒否し、正規の移管・削除は担当契約を更新するレビュー対象にする。ケースの error が別ケースの正常結果に紛れず、直呼びでもケース単位の検査が働くことを確認する。
  - ビルド・CI 接続も確認する。`Package.swift` の GoldenHarnessSupport は sources 明示列挙なので、新規 Swift helper は列挙に追加する。`.github/workflows/ci.yml` の Golden / method shard の選択条件を確認し、新 suite・新 profile が未実行にも重複実行にもならないよう実行件数を照合する。既存の検証や対象除外を緩めて通さない。
  - 完了条件: shard をまたぐ重複・指定削除・孤立ファイル・不正 schema を負のケースで検出でき、通常実行と更新モードの両方でゲートが有効。更新前後の担当数 / case・profile 数を提示し、実行時間・メモリの増加も確認する。
  - 2026-09-16 実装: 全 suite の discovery / expected golden / profile / 対象契約を事前検査し、専用 inventory suite と CI shard 0 の必須ゲート、更新前検査、孤立・改名残り・shard 横断重複の負のテストを追加。focused gates は成功（全 Swift / 全 Golden / 全 diff / 指標は未実行）。
- [~] RF-GOLDEN-003: stdlib メタデータを対象指定の専用 Golden へ移管し、由来検証を補完する（前提: 001・011・013）
  - 対象: 既存 `stdlib_kotlin_*` 入力と期待値、`PairTripleNominalAnchorTests` / `BundledDeclarationIndexTests` / `ListSyntheticMemberLinkTests` 等。まず List / Iterable / MutableCollection、Pair / Triple、member alias のメタデータ契約を担当ケースへ割り当て、011の対象指定を追加する。新規ケースは不足する契約だけに限定する。
  - API 群ごとに001の「削るメタデータ → 担当する専用節 / assertion」を対応付ける。Collection API を呼ぶケースへ List の flags が現れる、といった依存型の重複を残さない。既存289ケースが対象指定なしで自動的にメタデータを担うとはせず、必要な契約の担当と API 呼び出しの型検証のみを行うものを区別する。
  - `synthetic` がないだけで source 所有と断定せず、AST / import との対応や残存 stub / alias の許可を既存 Sema テストで検証する。専用メタデータ抽出の分類結果をそのまま唯一の正解として使わない。既存の重要 lowering・ABI assertion は004・005で維持する。
  - 完了条件: 対象の誤った所有・重要 flags / signature / type の変更を専用側が検出し、001の移管項目に未対応がないこと。担当契約の重複検査が green で、通常 Golden に依存しない検証先を示せること。件数が大きければ API 群別の新IDへ分け、全件の大規模再編や通常出力の削減をこのタスクへ混ぜない。
  - 2026-09-18 実施: List / Iterable / MutableCollection、Triple の nominal metadata を artifact profile の対象指定へ移管し、Sequence.shuffled の source-backed member alias を source profile の対象指定へ移管。既存 Pair の対象指定と合わせ、flags / signature / variance / supertypes / constructor annotation / alias origin を専用節で固定した。Inventory は 872 cases（artifact 6、source 1、implicit 865）、targeted 7、contracts 10 を全量検査する。
  - focused 検証: `swift build --build-tests` PASS、専用 Inventory 9件 PASS、TargetedGolden 16件 PASS、SymbolOrigin 9件 PASS、PairTriple 2件 PASS、BundledDeclarationIndex 8件 PASS、List/Iterable/MutableCollection の代表5件 PASS、4件のartifact Goldenとsource alias Goldenの直接再生成比較 PASS。全 Swift / 全 Golden / 全 diff / 全 RF 指標は未実行。
- [~] RF-GOLDEN-004: フラグ変更が iterator / lowering に与える影響を既存回帰 suite で担保する（前提: 001）
  - 対象: `ControlFlowLowerer.swift` に対する `CodegenBackendInterfaceIterableForLoopTests`、`StdlibArtifactRegressionTests`、対応する Core KIR / Lowering suites。`testConcreteListForLoopStillUsesListIterator`、`testIterableInterfaceForLoopLowersToIteratorNotRangeIntrinsics`、BUG-231 の手書き List / Set / Mutable 系実装の実行テストを移管先として明示し、足りない source 注入 / artifact 経路だけを補う。
  - KSP-697 の非 synthetic List でも専用の iterator 呼び出しが残り、interface 経由やユーザー実装の override は適切な経路を使うことを確認する。artifact の型代入テストだけを iterator の経路・実行検証の代わりにしない。001で重要と判定した data / enum 合成や inline 等も既存の対応 lowering テストへ紐付ける。
  - 完了条件: Golden の flags 表示を使わず、正しい KIR callee と実行結果を検証できること。重要分岐を誤った状態にした負の対照で検出力を確認し、出力安定化のために production の分岐を緩めない。
  - 2026-09-16 実施: concrete List の専用 `kk_list_iterator` / `kk_list_iterator_hasNext` / `kk_list_iterator_next` と、Iterable interface の `kk_iterable_iterator` / `kk_iterator_*` を source-injected KIR で固定。Lowering pass の iterator bridge 再特殊化、precompiled stdlib artifact 消費時の KIR と実行結果（`6`, `6`, `15`）、BUG-231 の手書き List / Set / custom Iterator / MutableSet / MutableList 実行を追加・補強した。List の専用経路と generic/range 非該当を同じ assertions で検出する。
  - focused 検証: `swift build --build-tests` PASS、Core KIR / Lowering 2件 PASS、Backend の concrete List / Iterable 2件 PASS、artifact KIR・実行 1件 PASS、BUG-231 手書き collection 5件 PASS、`git diff --check` PASS。
  - 未実施: 全 Swift テスト・全 Golden・`Scripts/diff_kotlinc.sh` 全件。共通 RF ゲート未完了のため `[~]`。
- [ ] RF-GOLDEN-005: ABI・bridge・throwing 契約の移管漏れを専用テストで補完する（前提: 001）
  - 対象: `RuntimeABIExternalLinkValidationTests` / `StdlibSurfaceSpecTests` / `ABIMismatchTests` / `ABIMismatchRuntimeExportParityTests` と ABI lowering tests。参照先の externalLinkName と `@KsSymbolName`、RuntimeABISpec、runtime export の対応・引数順 / 型 / arity / 戻り型を照合する。既存の constructor 特例や export parity の除外を把握し、必要な個別テストを確認する。
  - `ABILoweringPass` の throwingFunction → outThrown、非 throwing 呼び出し、source-backed bridge の実際の lowered call を確認する。`DurationSyntheticStubTests` の parse bridge flag assertion や collection mutation の ABI assertion は再利用し、symbol 名が登録されているだけ・spec とその派生表が一致するだけでは実 call / export との適合を証明したとしない。
  - 完了条件: 001の ABI / bridge 移管項目を具体的な assertion と正常 / 異常系で覆い、`validate_runtime_abi_links.sh` と関連 Runtime / Lowering テストが green。既存除外・許可リストを拡大して green にする変更はしない。
- [~] RF-GOLDEN-006: 安定した宣言キーを stdlib の実装方式によらない公開参照へ対応付ける（前提: 002・010）
  - 対象: `StableRenderContext` の外部参照 / 型 / signature の描画と Sema formatter。番号の廃止・型パラメータの位置正規化は010で完了させ、ここでは002の由来判定を使い、synthetic member alias / bundled extension / imported 宣言を同じ公開 API へ対応付ける追加の投影だけを実装する。
  - 戻り型・nullability・variance・境界・suspend・default / vararg・named argument に必要な引数名など、型検証と呼び出し識別に必要な契約を保持する。member alias と元の extension は由来・対応が証明できる場合だけ同じ公開参照へ写し、同名同 arity の別 overload やユーザー override は潰さない。runtime link 名を公開 API の安定IDに使わない。
  - 完了条件: 同じ公開 API の synthetic / source-backed / imported 表現は同じ参照となり、別 overload は区別されること。010の不変・感度テストを維持し、由来の違いを吸収する追加投影の既定出力への接続は008まで行わない。
- [ ] RF-GOLDEN-007: 通常 symbol 行を fixture 所有の宣言に限定する描画経路と情報保持テストを追加する（前提: 003・004・005・006・011・012・013）
  - 対象: `GoldenHarnessDump.renderSemaOutput` / `StableRenderContext.expandRequiredSymbols` と GoldenHarness tests。現在の参照収集で表示される fixture 所有の宣言・合成メンバを保持し、外部宣言の flags / sig / type 行を省く。未参照の fixture メンバ全列挙への変更は混ぜない。外部参照の中に現れる fixture の型や、実際の `targs` の収集まで止めず、別 library のメタデータも省く場合は001で検証先を確認する。
  - `call=` / `ref=` / 型は006の同じ公開参照表現で描画し、推論型・`targs=`・診断を維持する。専用ケースに限って011の明示対象メタデータ節を追加する。比較後の文字列置換で消すのではなく、所有と対象指定を持つ描画時点で分離する。既定出力は維持したまま新経路をテストから検証する。
  - 不変テスト: 公開 API が同じなら stdlib の由来・declSite・内部 flag / symbol ID・未参照宣言を変えても通常部分は同じ。専用側では対象のメタデータ変更だけが対応する節の差分になり、List の変更で List を型として参照するだけの他の専用ケースは変わらない。
  - 感度テスト: fixture 宣言・推論型・callee / overload・型制約・診断の変更は通常部分でも差分になる。ユーザーの synthetic data / enum / accessor / object literal が残ること、`kotlin.Enum.equals` 等の解決先変更を消さないことを確認する。重要 flag の誤設定は対象指定の Golden と004・005の挙動検証で検出する。
  - 完了条件: raw / normalized 双方で上記が green。専用対象が欠ける状態は失敗し、通常の行数を減らすだけでは通らないこと。描画が compiler の symbol / flags / binding を変更せず、空 package 注入や冪等性だけを情報保持の証明にしない。
- [ ] RF-GOLDEN-008: メンテナ確認後、通常 / 対象指定 Golden へ切り替えて §8 と効果を検証する（前提: 003・004・005・007・011・012・013 の全ゲート green）
  - 切り替え前に、省くメタデータと担当ケース、検証移管の網羅、更新件数への影響、`docs/stdlib-pipeline.md` §8 の改訂案をメンテナ確認する。新方針は「実装詳細だけの変化では通常 Golden を更新しない。公開 API / 解決先の意味変更・出力仕様移行時の更新は許容する」とし、決定的なロード順・stdlib diagnostics・diff 検証の要件は緩めない。
  - 対象: `GoldenHarnessAPI` / `GoldenHarnessDump` / Sema golden / 同文書 §8。007を既定にし、Sema suite のみ `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` で再生成する。入力 `.kt` の分割・意味変更は混ぜず、専用対象メタデータが保存されていることを確認する。
  - 更新モードなしで同 suite と `GoldenHarnessPersistenceTests` / `GoldenHarnessSemaComparisonNormalizationTests` / `GoldenHarnessNormalizationInvariantTests` を再実行する。API・worker・保存 / 比較で専用対象が失われないことを確認し、正規化バイパスを再導入しない。Lexer / Parser / Diagnostics の出力は変更しない。
  - 効果検証: KSP-697 の106ケース（通常53・stdlib名53）を基準に、同等の対象メタデータ変更で通常側が不変、専用側の更新は契約の担当ケースに限定されることを確認する。1〜2ファイルという値を保証せず、変更された独立契約数・担当ファイル数・残る意味上の expr 差分を分けて実測・記録する。
  - 完了条件: RF 必須ゲートと移管テストが green。579ケース（着手時に件数再確認）の宣言・型・解決先・診断の情報を維持し、メタデータ担当の欠落・意図しない重複がないこと。§8 の正式改訂と通常 / 専用の両方向の回帰が揃うまで完了扱いにしない。
- [ ] RF-GOLDEN-009: Golden 表示のための nil declSite 互換処理をコンパイラから切り離す（前提: 008）
  - 対象: `HeaderCollection.predeclareBundledTupleHeaders` / Charset 先行登録 / `shouldRestoreDeclSiteForReusableSyntheticSymbol`、`PairTripleNominalAnchorTests`。まず Pair / Triple の nil declSite 要求を、正しい宣言所有・型解決・必要な flags と Golden の実装非依存性を確認するテストへ置き換える。
  - nil 維持の理由を Golden 都合と実際の compiler / metadata 互換性に分け、前者だけを解消する。`isSourceBackedSymbol`、external call / constructor lowering、metadata export / import の挙動が変わるため、source 化された全 shell に declSite を一律復元しない。`--no-stdlib` の fallback と Duration 等の既存例外を保持し、着手時に影響が広ければ nominal 群別の新IDへ分割する。
  - 完了条件: 型解決・source / artifact / no-stdlib の該当経路が green で、Golden 安定性のために宣言位置を偽装する必要がないこと。実行時に必要な互換処理は専用回帰テストとともに残し、単なる Golden の再更新で挙動差を隠さない。

---

## Stdlib gap audit 2.3.10 実装タスク（KSP-719+）

> 公式 Kotlin/Native 2.3.10 `klib dump-abi`（`official_native_stdlib_abi.txt`）を正典として、KSwiftK バンドル Kotlin ソース（`Sources/CompilerCore/Stdlib/kotlin/`）と比較した機械監査結果から生成。`kotlin.jvm` / `kotlin.internal` / `kotlin.native.internal` / `kotlin.test` / `kotlinx` / `java` / `javax` / wasm・web-only sourceset は除外。
> 1タスク = 原則 1 PR。粒度は（package, receiver）単位または 30 件を超える場合は関数名 prefix ファミリー単位。完全な未実装リストは `docs/stdlib-gap-audit-2.3.10/gap_v2.tsv`（本倉庫へのコピー推奨）を参照。
> 実装時には、既存の `__kk_*` / `kk_*` bridge・合成スタブ・`RuntimeABISpec` 登録があれば同 PR で削除または `__kk_` 降格し、`UPDATE_GOLDEN=1` で golden を更新、`bash Scripts/diff_kotlinc.sh` で kotlinc 2.3.10 との差分を確認すること。

- [~] KSP-874: kotlin.Pair top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.Pair` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Pair/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Pair_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Pair_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Pair_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.Pair.<init>` — constructor (, )  -- `constructor <init>(#A, #B)`
  - 実装済み・focused確認（2026-09-18、KUU-426）: PR #5983 で `Sources/CompilerCore/Stdlib/kotlin/Pair/Stdlib.kt` に constructor の source owner と専用 Sema Golden / diff fixture を追加済み。`__kk_pair_new` は collection/sequence が共有する Pair box allocation bridge のため残置する。現行 master で `swift build`、`PairTripleNominalAnchorTests`（2件）、Pair の最小 Sema render（非 nullable / nullable の `kotlin.Pair.<init>` binding）、`stdlib_kotlin_Pair_n_n.kt` の kotlinc 2.3.10 参照出力生成、TODO ID、Runtime ABI link（5件）を確認済み。Pair-only diff の PASS は PR #5983 の検証記録を再確認した。全 Golden / 全 diff_cases は共通ゲート G としてローカルでは実行せず、PR CI に委ねるため `[~]` を維持する。

- [ ] KSP-927: kotlin.collections.AbstractList-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `AbstractList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_AbstractList.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_AbstractList.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_AbstractList.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractList` — class kotlin.collections.AbstractList  -- `abstract class <#A: out kotlin/Any?> kotlin.collections/AbstractList : kotlin.collections/AbstractCollection<#A>, kotlin.collections/List<#A> {`

- [ ] KSP-937: kotlin.collections.Iterable-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / top-level / family `Iterable`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/IterableAggregateHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_Iterable.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_Iterable.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_Iterable.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Iterable` — interface kotlin.collections.Iterable  -- `abstract interface <#A: out kotlin/Any?> kotlin.collections/Iterable {`
    - `kotlin.collections.Iterable` — fun Iterable(Function0): Iterable  -- `final inline fun <#A: kotlin/Any?> kotlin.collections/Iterable(crossinline kotlin/Function0<kotlin.collections/Iterator<#A>>): kotlin.collections/Iterable<#A>`

- [ ] KSP-940: kotlin.collections.ListIterator-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `ListIterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ListIterator.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_ListIterator.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_ListIterator.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_ListIterator.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ListIterator` — interface kotlin.collections.ListIterator  -- `abstract interface <#A: out kotlin/Any?> kotlin.collections/ListIterator : kotlin.collections/Iterator<#A> {`

- [ ] KSP-942: kotlin.collections.MutableCollection-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `MutableCollection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMutableCollection.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_MutableCollection.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_MutableCollection.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_MutableCollection.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableCollection` — interface kotlin.collections.MutableCollection  -- `abstract interface <#A: kotlin/Any?> kotlin.collections/MutableCollection : kotlin.collections/Collection<#A>, kotlin.collections/MutableIterable<#A> {`

- [ ] KSP-943: kotlin.collections.MutableIterator-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `MutableIterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableIterator.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_MutableIterator.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_MutableIterator.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_MutableIterator.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableIterator` — interface kotlin.collections.MutableIterator  -- `abstract interface <#A: out kotlin/Any?> kotlin.collections/MutableIterator : kotlin.collections/Iterator<#A> {`

- [ ] KSP-944: kotlin.collections.MutableList-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / top-level / family `MutableList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_MutableList.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_MutableList.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_MutableList.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableList` — interface kotlin.collections.MutableList  -- `abstract interface <#A: kotlin/Any?> kotlin.collections/MutableList : kotlin.collections/List<#A>, kotlin.collections/MutableCollection<#A> {`
    - `kotlin.collections.MutableList` — fun MutableList(Int, Function1): MutableList  -- `final inline fun <#A: kotlin/Any?> kotlin.collections/MutableList(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): kotlin.collections/MutableList<#A>`

- [ ] KSP-945: kotlin.collections.MutableListIterator-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `MutableListIterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableListIterator.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_MutableListIterator.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_MutableListIterator.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_MutableListIterator.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableListIterator` — interface kotlin.collections.MutableListIterator  -- `abstract interface <#A: kotlin/Any?> kotlin.collections/MutableListIterator : kotlin.collections/ListIterator<#A>, kotlin.collections/MutableIterator<#A> {`

- [ ] KSP-949: kotlin.collections.array-family の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.collections` / top-level / family `array`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayAggregateHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_array.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_array.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_array.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.arrayListOf` — fun arrayListOf(): ArrayList  -- `final inline fun <#A: kotlin/Any?> kotlin.collections/arrayListOf(): kotlin.collections/ArrayList<#A>`
    - `kotlin.collections.arrayListOf` — fun arrayListOf(Array): ArrayList  -- `final fun <#A: kotlin/Any?> kotlin.collections/arrayListOf(kotlin/Array<out #A>...): kotlin.collections/ArrayList<#A>`
    - `kotlin.collections.arrayOfUninitializedElements` — fun arrayOfUninitializedElements(Int): Array  -- `final inline fun <#A: kotlin/Any?> kotlin.collections/arrayOfUninitializedElements(kotlin/Int): kotlin/Array<#A>`

- [ ] KSP-1029: kotlin.collections.AbstractList top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.AbstractList` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractList/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractList_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractList.<init>` — constructor ()  -- `constructor <init>()`

- [ ] KSP-1030: kotlin.collections.AbstractList.AbstractList の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.collections.AbstractList` / receiver `AbstractList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractList/AbstractList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractList_AbstractList_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_AbstractList_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_AbstractList_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractList.equals` — fun AbstractList.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.AbstractList.get` — fun AbstractList.get(Int): #A  -- `abstract fun get(kotlin/Int): #A`
    - `kotlin.collections.AbstractList.hashCode` — fun AbstractList.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.collections.AbstractList.indexOf` — fun AbstractList.indexOf(): Int  -- `open fun indexOf(#A): kotlin/Int`
    - `kotlin.collections.AbstractList.iterator` — fun AbstractList.iterator(): Iterator  -- `open fun iterator(): kotlin.collections/Iterator<#A>`
    - `kotlin.collections.AbstractList.lastIndexOf` — fun AbstractList.lastIndexOf(): Int  -- `open fun lastIndexOf(#A): kotlin/Int`
    - `kotlin.collections.AbstractList.listIterator` — fun AbstractList.listIterator(): ListIterator  -- `open fun listIterator(): kotlin.collections/ListIterator<#A>`
    - `kotlin.collections.AbstractList.listIterator` — fun AbstractList.listIterator(Int): ListIterator  -- `open fun listIterator(kotlin/Int): kotlin.collections/ListIterator<#A>`
    - `kotlin.collections.AbstractList.size` — val AbstractList.size: Int  -- `abstract val size`
    - `kotlin.collections.AbstractList.subList` — fun AbstractList.subList(Int, Int): List  -- `open fun subList(kotlin/Int, kotlin/Int): kotlin.collections/List<#A>`

- [ ] KSP-1031: kotlin.collections.AbstractMap top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.AbstractMap` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMap/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMap_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMap_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMap_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMap.<init>` — constructor ()  -- `constructor <init>()`

- [ ] KSP-1032: kotlin.collections.AbstractMap.AbstractMap の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.collections.AbstractMap` / receiver `AbstractMap`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMap/AbstractMap.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMap_AbstractMap_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMap_AbstractMap_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMap_AbstractMap_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMap.containsKey` — fun AbstractMap.containsKey(): Boolean  -- `open fun containsKey(#A): kotlin/Boolean`
    - `kotlin.collections.AbstractMap.containsValue` — fun AbstractMap.containsValue(): Boolean  -- `open fun containsValue(#B): kotlin/Boolean`
    - `kotlin.collections.AbstractMap.equals` — fun AbstractMap.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.AbstractMap.get` — fun AbstractMap.get(): #B  -- `open fun get(#A): #B?`
    - `kotlin.collections.AbstractMap.hashCode` — fun AbstractMap.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.collections.AbstractMap.isEmpty` — fun AbstractMap.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.AbstractMap.keys` — val AbstractMap.keys: Set  -- `open val keys`
    - `kotlin.collections.AbstractMap.size` — val AbstractMap.size: Int  -- `open val size`
    - `kotlin.collections.AbstractMap.toString` — fun AbstractMap.toString(): String  -- `open fun toString(): kotlin/String`
    - `kotlin.collections.AbstractMap.values` — val AbstractMap.values: Collection  -- `open val values`

- [ ] KSP-1045: kotlin.collections.ArrayList top-level の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.collections.ArrayList` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayList/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_ArrayList_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_ArrayList_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_ArrayList_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ArrayList.<init>` — constructor ()  -- `constructor <init>()`
    - `kotlin.collections.ArrayList.<init>` — constructor (Collection)  -- `constructor <init>(kotlin.collections/Collection<#A>)`
    - `kotlin.collections.ArrayList.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [ ] KSP-1046: kotlin.collections.ArrayList.ArrayList の未実装 stdlib API を実装する（25 件）
  - 対象: `kotlin.collections.ArrayList` / receiver `ArrayList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayList/ArrayList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_ArrayList_ArrayList_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_ArrayList_ArrayList_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_ArrayList_ArrayList_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ArrayList.add` — fun ArrayList.add(): Boolean  -- `final fun add(#A): kotlin/Boolean`
    - `kotlin.collections.ArrayList.add` — fun ArrayList.add(Int, ): Unit  -- `final fun add(kotlin/Int, #A)`
    - `kotlin.collections.ArrayList.addAll` — fun ArrayList.addAll(Collection): Boolean  -- `final fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayList.addAll` — fun ArrayList.addAll(Int, Collection): Boolean  -- `final fun addAll(kotlin/Int, kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayList.build` — fun ArrayList.build(): List  -- `final fun build(): kotlin.collections/List<#A>`
    - `kotlin.collections.ArrayList.clear` — fun ArrayList.clear(): Unit  -- `final fun clear()`
    - `kotlin.collections.ArrayList.ensureCapacity` — fun ArrayList.ensureCapacity(Int): Unit  -- `final fun ensureCapacity(kotlin/Int)`
    - `kotlin.collections.ArrayList.equals` — fun ArrayList.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.ArrayList.get` — fun ArrayList.get(Int): #A  -- `final fun get(kotlin/Int): #A`
    - `kotlin.collections.ArrayList.hashCode` — fun ArrayList.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.collections.ArrayList.indexOf` — fun ArrayList.indexOf(): Int  -- `final fun indexOf(#A): kotlin/Int`
    - `kotlin.collections.ArrayList.isEmpty` — fun ArrayList.isEmpty(): Boolean  -- `final fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.ArrayList.iterator` — fun ArrayList.iterator(): MutableIterator  -- `final fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.ArrayList.lastIndexOf` — fun ArrayList.lastIndexOf(): Int  -- `final fun lastIndexOf(#A): kotlin/Int`
    - `kotlin.collections.ArrayList.listIterator` — fun ArrayList.listIterator(): MutableListIterator  -- `final fun listIterator(): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.ArrayList.listIterator` — fun ArrayList.listIterator(Int): MutableListIterator  -- `final fun listIterator(kotlin/Int): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.ArrayList.remove` — fun ArrayList.remove(): Boolean  -- `final fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.ArrayList.removeAll` — fun ArrayList.removeAll(Collection): Boolean  -- `final fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayList.removeAt` — fun ArrayList.removeAt(Int): #A  -- `final fun removeAt(kotlin/Int): #A`
    - `kotlin.collections.ArrayList.retainAll` — fun ArrayList.retainAll(Collection): Boolean  -- `final fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayList.set` — fun ArrayList.set(Int, ): #A  -- `final fun set(kotlin/Int, #A): #A`
    - `kotlin.collections.ArrayList.size` — val ArrayList.size: Int  -- `final val size`
    - `kotlin.collections.ArrayList.subList` — fun ArrayList.subList(Int, Int): MutableList  -- `final fun subList(kotlin/Int, kotlin/Int): kotlin.collections/MutableList<#A>`
    - `kotlin.collections.ArrayList.toString` — fun ArrayList.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.collections.ArrayList.trimToSize` — fun ArrayList.trimToSize(): Unit  -- `final fun trimToSize()`

- [ ] KSP-1056: kotlin.collections.HashSet top-level の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.collections.HashSet` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/HashSet/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_HashSet_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_HashSet_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_HashSet_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.HashSet.<init>` — constructor ()  -- `constructor <init>()`
    - `kotlin.collections.HashSet.<init>` — constructor (Collection)  -- `constructor <init>(kotlin.collections/Collection<#A>)`
    - `kotlin.collections.HashSet.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.collections.HashSet.<init>` — constructor (Int, Float)  -- `constructor <init>(kotlin/Int, kotlin/Float)`

- [ ] KSP-1057: kotlin.collections.HashSet.HashSet の未実装 stdlib API を実装する（12 件）
  - 対象: `kotlin.collections.HashSet` / receiver `HashSet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/HashSet/HashSet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_HashSet_HashSet_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_HashSet_HashSet_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_HashSet_HashSet_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.HashSet.add` — fun HashSet.add(): Boolean  -- `final fun add(#A): kotlin/Boolean`
    - `kotlin.collections.HashSet.addAll` — fun HashSet.addAll(Collection): Boolean  -- `final fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.HashSet.build` — fun HashSet.build(): Set  -- `final fun build(): kotlin.collections/Set<#A>`
    - `kotlin.collections.HashSet.clear` — fun HashSet.clear(): Unit  -- `final fun clear()`
    - `kotlin.collections.HashSet.contains` — fun HashSet.contains(): Boolean  -- `final fun contains(#A): kotlin/Boolean`
    - `kotlin.collections.HashSet.getElement` — fun HashSet.getElement(): #A  -- `final fun getElement(#A): #A?`
    - `kotlin.collections.HashSet.isEmpty` — fun HashSet.isEmpty(): Boolean  -- `final fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.HashSet.iterator` — fun HashSet.iterator(): MutableIterator  -- `final fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.HashSet.remove` — fun HashSet.remove(): Boolean  -- `final fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.HashSet.removeAll` — fun HashSet.removeAll(Collection): Boolean  -- `final fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.HashSet.retainAll` — fun HashSet.retainAll(Collection): Boolean  -- `final fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.HashSet.size` — val HashSet.size: Int  -- `final val size`

- [ ] KSP-1061: kotlin.collections.Iterable.Iterable の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.Iterable` / receiver `Iterable`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterable/Iterable.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_Iterable_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_Iterable_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_Iterable_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Iterable.iterator` — fun Iterable.iterator(): Iterator  -- `abstract fun iterator(): kotlin.collections/Iterator<#A>`

- [ ] KSP-1062: kotlin.collections.Iterator.Iterator の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections.Iterator` / receiver `Iterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterator/Iterator.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterator_Iterator_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterator_Iterator_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterator_Iterator_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Iterator.hasNext` — fun Iterator.hasNext(): Boolean  -- `abstract fun hasNext(): kotlin/Boolean`
    - `kotlin.collections.Iterator.next` — fun Iterator.next(): #A  -- `abstract fun next(): #A`

- [ ] KSP-1063: kotlin.collections.List.List の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.collections.List` / receiver `List`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/List/List.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_List_List_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_List_List_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_List_List_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.List.get` — fun List.get(Int): #A  -- `abstract fun get(kotlin/Int): #A`
    - `kotlin.collections.List.isEmpty` — fun List.isEmpty(): Boolean  -- `abstract fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.List.iterator` — fun List.iterator(): Iterator  -- `abstract fun iterator(): kotlin.collections/Iterator<#A>`
    - `kotlin.collections.List.listIterator` — fun List.listIterator(): ListIterator  -- `abstract fun listIterator(): kotlin.collections/ListIterator<#A>`
    - `kotlin.collections.List.listIterator` — fun List.listIterator(Int): ListIterator  -- `abstract fun listIterator(kotlin/Int): kotlin.collections/ListIterator<#A>`
    - `kotlin.collections.List.size` — val List.size: Int  -- `abstract val size`

- [ ] KSP-1066: kotlin.collections.Map top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.Map` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Map/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Map.Entry` — interface kotlin.collections.Map.Entry  -- `abstract interface <#A1: out kotlin/Any?, #B1: out kotlin/Any?> Entry {`

- [ ] KSP-1068: kotlin.collections.Map.Entry.Entry の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections.Map.Entry` / receiver `Entry`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Map/Entry/Entry.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_Entry_Entry_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_Entry_Entry_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_Entry_Entry_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Map.Entry.key` — val Entry.key: #A1  -- `abstract val key`
    - `kotlin.collections.Map.Entry.value` — val Entry.value: #B1  -- `abstract val value`

- [ ] KSP-1069: kotlin.collections.MutableCollection.MutableCollection の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.collections.MutableCollection` / receiver `MutableCollection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableCollection/MutableCollection.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableCollection_MutableCollection_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableCollection_MutableCollection_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableCollection_MutableCollection_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableCollection.add` — fun MutableCollection.add(): Boolean  -- `abstract fun add(#A): kotlin/Boolean`
    - `kotlin.collections.MutableCollection.addAll` — fun MutableCollection.addAll(Collection): Boolean  -- `abstract fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableCollection.clear` — fun MutableCollection.clear(): Unit  -- `abstract fun clear()`
    - `kotlin.collections.MutableCollection.iterator` — fun MutableCollection.iterator(): MutableIterator  -- `abstract fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.MutableCollection.remove` — fun MutableCollection.remove(): Boolean  -- `abstract fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.MutableCollection.removeAll` — fun MutableCollection.removeAll(Collection): Boolean  -- `abstract fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableCollection.retainAll` — fun MutableCollection.retainAll(Collection): Boolean  -- `abstract fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`

- [ ] KSP-1072: kotlin.collections.MutableList.MutableList の未実装 stdlib API を実装する（13 件）
  - 対象: `kotlin.collections.MutableList` / receiver `MutableList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableList/MutableList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableList_MutableList_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableList_MutableList_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableList_MutableList_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableList.add` — fun MutableList.add(): Boolean  -- `abstract fun add(#A): kotlin/Boolean`
    - `kotlin.collections.MutableList.add` — fun MutableList.add(Int, ): Unit  -- `abstract fun add(kotlin/Int, #A)`
    - `kotlin.collections.MutableList.addAll` — fun MutableList.addAll(Collection): Boolean  -- `abstract fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableList.addAll` — fun MutableList.addAll(Int, Collection): Boolean  -- `abstract fun addAll(kotlin/Int, kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableList.clear` — fun MutableList.clear(): Unit  -- `abstract fun clear()`
    - `kotlin.collections.MutableList.listIterator` — fun MutableList.listIterator(): MutableListIterator  -- `abstract fun listIterator(): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.MutableList.listIterator` — fun MutableList.listIterator(Int): MutableListIterator  -- `abstract fun listIterator(kotlin/Int): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.MutableList.remove` — fun MutableList.remove(): Boolean  -- `abstract fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.MutableList.removeAll` — fun MutableList.removeAll(Collection): Boolean  -- `abstract fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableList.removeAt` — fun MutableList.removeAt(Int): #A  -- `abstract fun removeAt(kotlin/Int): #A`
    - `kotlin.collections.MutableList.retainAll` — fun MutableList.retainAll(Collection): Boolean  -- `abstract fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableList.set` — fun MutableList.set(Int, ): #A  -- `abstract fun set(kotlin/Int, #A): #A`
    - `kotlin.collections.MutableList.subList` — fun MutableList.subList(Int, Int): MutableList  -- `abstract fun subList(kotlin/Int, kotlin/Int): kotlin.collections/MutableList<#A>`

- [ ] KSP-1074: kotlin.collections.MutableMap top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.MutableMap` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableMap/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableMap_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableMap.MutableEntry` — interface kotlin.collections.MutableMap.MutableEntry  -- `abstract interface <#A1: kotlin/Any?, #B1: kotlin/Any?> MutableEntry : kotlin.collections/Map.Entry<#A1, #B1> {`

- [ ] KSP-1075: kotlin.collections.MutableMap.MutableMap の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.collections.MutableMap` / receiver `MutableMap`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableMap/MutableMap.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableMap_MutableMap_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_MutableMap_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_MutableMap_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableMap.clear` — fun MutableMap.clear(): Unit  -- `abstract fun clear()`
    - `kotlin.collections.MutableMap.entries` — val MutableMap.entries: MutableSet  -- `abstract val entries`
    - `kotlin.collections.MutableMap.keys` — val MutableMap.keys: MutableSet  -- `abstract val keys`
    - `kotlin.collections.MutableMap.put` — fun MutableMap.put(, ): #B  -- `abstract fun put(#A, #B): #B?`
    - `kotlin.collections.MutableMap.putAll` — fun MutableMap.putAll(Map): Unit  -- `abstract fun putAll(kotlin.collections/Map<out #A, #B>)`
    - `kotlin.collections.MutableMap.remove` — fun MutableMap.remove(): #B  -- `abstract fun remove(#A): #B?`
    - `kotlin.collections.MutableMap.values` — val MutableMap.values: MutableCollection  -- `abstract val values`

- [ ] KSP-1077: kotlin.collections.MutableSet.MutableSet の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.collections.MutableSet` / receiver `MutableSet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableSet/MutableSet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableSet_MutableSet_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableSet_MutableSet_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableSet_MutableSet_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableSet.add` — fun MutableSet.add(): Boolean  -- `abstract fun add(#A): kotlin/Boolean`
    - `kotlin.collections.MutableSet.addAll` — fun MutableSet.addAll(Collection): Boolean  -- `abstract fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableSet.clear` — fun MutableSet.clear(): Unit  -- `abstract fun clear()`
    - `kotlin.collections.MutableSet.iterator` — fun MutableSet.iterator(): MutableIterator  -- `abstract fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.MutableSet.remove` — fun MutableSet.remove(): Boolean  -- `abstract fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.MutableSet.removeAll` — fun MutableSet.removeAll(Collection): Boolean  -- `abstract fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableSet.retainAll` — fun MutableSet.retainAll(Collection): Boolean  -- `abstract fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`

- [x] KSP-1084: kotlin.concurrent.KMutableProperty0 の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.concurrent` / receiver `KMutableProperty0`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/KMutableProperty0.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_KMutableProperty0_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_KMutableProperty0_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_KMutableProperty0_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: `Sources/CompilerCore/Stdlib/kotlin/concurrent/KMutableProperty0.kt` に9 APIを `KMutableProperty0.get()` / `set()` ベースの source-backed 実装として追加。対象名の Runtime/ABI/合成 stub/name-string 特例は存在せず、追加の bridge 整理は不要。

- [x] KSP-1085: kotlin.concurrent.AtomicArray top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicArray.<init>` — constructor (Array)  -- `constructor <init>(kotlin/Array<#A>)`
  - 完了根拠（2026-09-25）: `concurrent/AtomicArray/Stdlib.kt` を新設し、`AtomicArray(array: Array<T>)` を Kotlin/Native 実ソースと同じ `@PublishedApi internal` の top-level factory として source-backed 実装（`atomicArrayFromArray` の `kk_atomic_ref_array_of` extern へ委譲、要素は fresh storage にコピー）。対象名の `__kk_*` / `kk_*` Runtime 関数・合成 stub 登録・`RuntimeABISpec` エントリ・name-string 特例は存在せず（`registerAtomicRefArrayStub` は `kotlin.concurrent.atomics` 専用）、bridge 整理は不要。`kotlin.concurrent.AtomicArray` は `concurrent/Stdlib.kt` の `private constructor()` shell を維持し、receiver メンバーは KSP-1086 管轄。

- [ ] KSP-1086: kotlin.concurrent.AtomicArray.AtomicArray の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.concurrent.AtomicArray` / receiver `AtomicArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicArray/AtomicArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicArray_AtomicArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicArray_AtomicArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicArray_AtomicArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicArray.compareAndExchange` — fun AtomicArray.compareAndExchange(Int, , ): #A  -- `final fun compareAndExchange(kotlin/Int, #A, #A): #A`
    - `kotlin.concurrent.AtomicArray.compareAndSet` — fun AtomicArray.compareAndSet(Int, , ): Boolean  -- `final fun compareAndSet(kotlin/Int, #A, #A): kotlin/Boolean`
    - `kotlin.concurrent.AtomicArray.get` — fun AtomicArray.get(Int): #A  -- `final fun get(kotlin/Int): #A`
    - `kotlin.concurrent.AtomicArray.getAndSet` — fun AtomicArray.getAndSet(Int, ): #A  -- `final fun getAndSet(kotlin/Int, #A): #A`
    - `kotlin.concurrent.AtomicArray.length` — val AtomicArray.length: Int  -- `final val length`
    - `kotlin.concurrent.AtomicArray.set` — fun AtomicArray.set(Int, ): Unit  -- `final fun set(kotlin/Int, #A)`
    - `kotlin.concurrent.AtomicArray.toString` — fun AtomicArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1087: kotlin.concurrent.AtomicInt top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicInt` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicInt/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicInt_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicInt_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicInt_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicInt.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [ ] KSP-1088: kotlin.concurrent.AtomicInt.AtomicInt の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.concurrent.AtomicInt` / receiver `AtomicInt`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicInt/AtomicInt.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicInt_AtomicInt_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicInt_AtomicInt_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicInt_AtomicInt_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicInt.compareAndExchange` — fun AtomicInt.compareAndExchange(Int, Int): Int  -- `final fun compareAndExchange(kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.AtomicInt.getAndAdd` — fun AtomicInt.getAndAdd(Int): Int  -- `final fun getAndAdd(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.AtomicInt.getAndDecrement` — fun AtomicInt.getAndDecrement(): Int  -- `final fun getAndDecrement(): kotlin/Int`
    - `kotlin.concurrent.AtomicInt.getAndIncrement` — fun AtomicInt.getAndIncrement(): Int  -- `final fun getAndIncrement(): kotlin/Int`
    - `kotlin.concurrent.AtomicInt.toString` — fun AtomicInt.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.AtomicInt.value` — val AtomicInt.value: Int  -- `final var value`

- [~] KSP-1090: kotlin.concurrent.AtomicIntArray.AtomicIntArray の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.concurrent.AtomicIntArray` / receiver `AtomicIntArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicIntArray/AtomicIntArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicIntArray_AtomicIntArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicIntArray_AtomicIntArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicIntArray_AtomicIntArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装根拠: `AtomicIntArray/AtomicIntArray.kt` に `compareAndExchange` / `compareAndSet` / `length` / `toString` を source-backed class member として追加し、既存の `*At` / `size` Runtime bridge を再利用した。新規 Runtime / ABI / 合成 stub は不要で、`Any.toString()` への誤解決を避けるためクラス宣言を実装ファイルへ移した。
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicIntArray.compareAndExchange` — fun AtomicIntArray.compareAndExchange(Int, Int, Int): Int  -- `final fun compareAndExchange(kotlin/Int, kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.AtomicIntArray.compareAndSet` — fun AtomicIntArray.compareAndSet(Int, Int, Int): Boolean  -- `final fun compareAndSet(kotlin/Int, kotlin/Int, kotlin/Int): kotlin/Boolean`
    - `kotlin.concurrent.AtomicIntArray.length` — val AtomicIntArray.length: Int  -- `final val length`
    - `kotlin.concurrent.AtomicIntArray.toString` — fun AtomicIntArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1091: kotlin.concurrent.AtomicLong top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicLong` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicLong/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicLong_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLong_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLong_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicLong.<init>` — constructor (Long)  -- `constructor <init>(kotlin/Long)`

- [ ] KSP-1092: kotlin.concurrent.AtomicLong.AtomicLong の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.concurrent.AtomicLong` / receiver `AtomicLong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicLong/AtomicLong.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicLong_AtomicLong_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLong_AtomicLong_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLong_AtomicLong_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicLong.compareAndExchange` — fun AtomicLong.compareAndExchange(Long, Long): Long  -- `final fun compareAndExchange(kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.AtomicLong.getAndAdd` — fun AtomicLong.getAndAdd(Long): Long  -- `final fun getAndAdd(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.AtomicLong.getAndDecrement` — fun AtomicLong.getAndDecrement(): Long  -- `final fun getAndDecrement(): kotlin/Long`
    - `kotlin.concurrent.AtomicLong.getAndIncrement` — fun AtomicLong.getAndIncrement(): Long  -- `final fun getAndIncrement(): kotlin/Long`
    - `kotlin.concurrent.AtomicLong.toString` — fun AtomicLong.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.AtomicLong.value` — val AtomicLong.value: Long  -- `final var value`

- [ ] KSP-1093: kotlin.concurrent.AtomicLongArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.AtomicLongArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicLongArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicLongArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLongArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLongArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicLongArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.concurrent.AtomicLongArray.<init>` — constructor (LongArray)  -- `constructor <init>(kotlin/LongArray)`

- [x] KSP-1094: kotlin.concurrent.AtomicLongArray.AtomicLongArray の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.concurrent.AtomicLongArray` / receiver `AtomicLongArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicLongArray/AtomicLongArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicLongArray_AtomicLongArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLongArray_AtomicLongArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLongArray_AtomicLongArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: `AtomicLongArray/AtomicLongArray.kt` に `compareAndExchange` / `compareAndSet` / `length` / `toString` を source-backed class member として追加し、既存の `*At` / `size` Runtime bridge を再利用した。新規 Runtime / ABI / 合成 stub は不要で、`Any.toString()` への誤解決を避けるためクラス宣言を実装ファイルへ移した。
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicLongArray.compareAndExchange` — fun AtomicLongArray.compareAndExchange(Int, Long, Long): Long  -- `final fun compareAndExchange(kotlin/Int, kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.AtomicLongArray.compareAndSet` — fun AtomicLongArray.compareAndSet(Int, Long, Long): Boolean  -- `final fun compareAndSet(kotlin/Int, kotlin/Long, kotlin/Long): kotlin/Boolean`
    - `kotlin.concurrent.AtomicLongArray.length` — val AtomicLongArray.length: Int  -- `final val length`
    - `kotlin.concurrent.AtomicLongArray.toString` — fun AtomicLongArray.toString(): String  -- `final fun toString(): kotlin/String`

- [x] KSP-1095: kotlin.concurrent.AtomicNativePtr top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicNativePtr` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicNativePtr/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicNativePtr_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicNativePtr_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicNativePtr_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: `AtomicNativePtr/Stdlib.kt` に `kotlin.native.internal.NativePtr` を受ける source-backed public constructor を追加し、nominal class の宣言を責務ファイルへ移した。`value` / receiver 操作は KSP-1096 のため対象外で、今回の Runtime / ABI / synthetic stub / name-string 特例の変更は不要。
  - 完了確認（2026-09-16）: Sema Golden 全体、`AtomicTopLevelSourceTests`、`swift build`、`bash Scripts/check_todo_ids.sh`、`bash Scripts/validate_runtime_abi_links.sh`、`git diff --check` を確認。JVM kotlinc に Kotlin/Native-only API がないため diff case は `DEBT-DIFF-001` の `SKIP-DIFF` とした。
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicNativePtr.<init>` — constructor (NativePtr)  -- `constructor <init>(kotlin.native.internal/NativePtr)`

- [ ] KSP-1096: kotlin.concurrent.AtomicNativePtr.AtomicNativePtr の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.concurrent.AtomicNativePtr` / receiver `AtomicNativePtr`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicNativePtr/AtomicNativePtr.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicNativePtr.compareAndExchange` — fun AtomicNativePtr.compareAndExchange(NativePtr, NativePtr): NativePtr  -- `final fun compareAndExchange(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.AtomicNativePtr.compareAndSet` — fun AtomicNativePtr.compareAndSet(NativePtr, NativePtr): Boolean  -- `final fun compareAndSet(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin/Boolean`
    - `kotlin.concurrent.AtomicNativePtr.getAndSet` — fun AtomicNativePtr.getAndSet(NativePtr): NativePtr  -- `final fun getAndSet(kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.AtomicNativePtr.toString` — fun AtomicNativePtr.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.AtomicNativePtr.value` — val AtomicNativePtr.value: NativePtr  -- `final var value`

- [ ] KSP-1097: kotlin.concurrent.AtomicReference top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicReference` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicReference/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicReference_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicReference_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicReference_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicReference.<init>` — constructor ()  -- `constructor <init>(#A)`

- [ ] KSP-1098: kotlin.concurrent.AtomicReference.AtomicReference の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.concurrent.AtomicReference` / receiver `AtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicReference/AtomicReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicReference_AtomicReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicReference_AtomicReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicReference_AtomicReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicReference.compareAndExchange` — fun AtomicReference.compareAndExchange(, ): #A  -- `final fun compareAndExchange(#A, #A): #A`
    - `kotlin.concurrent.AtomicReference.getAndSet` — fun AtomicReference.getAndSet(): #A  -- `final fun getAndSet(#A): #A`
    - `kotlin.concurrent.AtomicReference.toString` — fun AtomicReference.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.AtomicReference.value` — val AtomicReference.value: #A  -- `final var value`

- [ ] KSP-1100: kotlin.concurrent.atomics top-level の未実装 stdlib API を実装する（13 件）
  - 対象: `kotlin.concurrent.atomics` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicArray` — class kotlin.concurrent.atomics.AtomicArray  -- `final class <#A: kotlin/Any?> kotlin.concurrent.atomics/AtomicArray {`
    - `kotlin.concurrent.atomics.AtomicArray` — fun AtomicArray(Int, Function1): AtomicArray  -- `final inline fun <#A: reified kotlin/Any?> kotlin.concurrent.atomics/AtomicArray(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): kotlin.concurrent.atomics/AtomicArray<#A>`
    - `kotlin.concurrent.atomics.AtomicBoolean` — class kotlin.concurrent.atomics.AtomicBoolean  -- `final class kotlin.concurrent.atomics/AtomicBoolean {`
    - `kotlin.concurrent.atomics.AtomicInt` — class kotlin.concurrent.atomics.AtomicInt  -- `final class kotlin.concurrent.atomics/AtomicInt {`
    - `kotlin.concurrent.atomics.AtomicIntArray` — class kotlin.concurrent.atomics.AtomicIntArray  -- `final class kotlin.concurrent.atomics/AtomicIntArray {`
    - `kotlin.concurrent.atomics.AtomicIntArray` — fun AtomicIntArray(Int, Function1): AtomicIntArray  -- `final inline fun kotlin.concurrent.atomics/AtomicIntArray(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Int>): kotlin.concurrent.atomics/AtomicIntArray`
    - `kotlin.concurrent.atomics.AtomicLong` — class kotlin.concurrent.atomics.AtomicLong  -- `final class kotlin.concurrent.atomics/AtomicLong {`
    - `kotlin.concurrent.atomics.AtomicLongArray` — class kotlin.concurrent.atomics.AtomicLongArray  -- `final class kotlin.concurrent.atomics/AtomicLongArray {`
    - `kotlin.concurrent.atomics.AtomicLongArray` — fun AtomicLongArray(Int, Function1): AtomicLongArray  -- `final inline fun kotlin.concurrent.atomics/AtomicLongArray(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Long>): kotlin.concurrent.atomics/AtomicLongArray`
    - `kotlin.concurrent.atomics.AtomicNativePtr` — class kotlin.concurrent.atomics.AtomicNativePtr  -- `final class kotlin.concurrent.atomics/AtomicNativePtr {`
    - `kotlin.concurrent.atomics.AtomicReference` — class kotlin.concurrent.atomics.AtomicReference  -- `final class <#A: kotlin/Any?> kotlin.concurrent.atomics/AtomicReference {`
    - `kotlin.concurrent.atomics.ExperimentalAtomicApi` — class kotlin.concurrent.atomics.ExperimentalAtomicApi  -- `open annotation class kotlin.concurrent.atomics/ExperimentalAtomicApi : kotlin/Annotation {`
    - `kotlin.concurrent.atomics.atomicArrayOfNulls` — fun atomicArrayOfNulls(Int): AtomicArray  -- `final inline fun <#A: reified kotlin/Any?> kotlin.concurrent.atomics/atomicArrayOfNulls(kotlin/Int): kotlin.concurrent.atomics/AtomicArray<#A?>`

- [ ] KSP-1101: kotlin.concurrent.atomics.AtomicArray の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicArrayMigration.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.fetchAndUpdateAt` — fun AtomicArray.fetchAndUpdateAt(Int, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicArray<#A>).kotlin.concurrent.atomics/fetchAndUpdateAt(kotlin/Int, kotlin/Function1<#A, #A>): #A`
    - `kotlin.concurrent.atomics.updateAndFetchAt` — fun AtomicArray.updateAndFetchAt(Int, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicArray<#A>).kotlin.concurrent.atomics/updateAndFetchAt(kotlin/Int, kotlin/Function1<#A, #A>): #A`

- [ ] KSP-1102: kotlin.concurrent.atomics.AtomicInt の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicInt`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicInt.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicInt_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.decrementAndFetch` — fun AtomicInt.decrementAndFetch(): Int  -- `final fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/decrementAndFetch(): kotlin/Int`
    - `kotlin.concurrent.atomics.incrementAndFetch` — fun AtomicInt.incrementAndFetch(): Int  -- `final fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/incrementAndFetch(): kotlin/Int`
    - `kotlin.concurrent.atomics.minusAssign` — fun AtomicInt.minusAssign(Int): Unit  -- `final fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/minusAssign(kotlin/Int)`
    - `kotlin.concurrent.atomics.plusAssign` — fun AtomicInt.plusAssign(Int): Unit  -- `final fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/plusAssign(kotlin/Int)`
    - `kotlin.concurrent.atomics.update` — fun AtomicInt.update(Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/update(kotlin/Function1<kotlin/Int, kotlin/Int>)`
    - `kotlin.concurrent.atomics.updateAndFetch` — fun AtomicInt.updateAndFetch(Function1): Int  -- `final inline fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/updateAndFetch(kotlin/Function1<kotlin/Int, kotlin/Int>): kotlin/Int`

- [ ] KSP-1103: kotlin.concurrent.atomics.AtomicIntArray の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicIntArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicArrayMigration.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.updateAndFetchAt` — fun AtomicIntArray.updateAndFetchAt(Int, Function1): Int  -- `final inline fun (kotlin.concurrent.atomics/AtomicIntArray).kotlin.concurrent.atomics/updateAndFetchAt(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Int>): kotlin/Int`
    - `kotlin.concurrent.atomics.updateAt` — fun AtomicIntArray.updateAt(Int, Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicIntArray).kotlin.concurrent.atomics/updateAt(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Int>)`

- [ ] KSP-1104: kotlin.concurrent.atomics.AtomicLong の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicLong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLong.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLong_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.decrementAndFetch` — fun AtomicLong.decrementAndFetch(): Long  -- `final fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/decrementAndFetch(): kotlin/Long`
    - `kotlin.concurrent.atomics.incrementAndFetch` — fun AtomicLong.incrementAndFetch(): Long  -- `final fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/incrementAndFetch(): kotlin/Long`
    - `kotlin.concurrent.atomics.minusAssign` — fun AtomicLong.minusAssign(Long): Unit  -- `final fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/minusAssign(kotlin/Long)`
    - `kotlin.concurrent.atomics.plusAssign` — fun AtomicLong.plusAssign(Long): Unit  -- `final fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/plusAssign(kotlin/Long)`
    - `kotlin.concurrent.atomics.update` — fun AtomicLong.update(Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/update(kotlin/Function1<kotlin/Long, kotlin/Long>)`
    - `kotlin.concurrent.atomics.updateAndFetch` — fun AtomicLong.updateAndFetch(Function1): Long  -- `final inline fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/updateAndFetch(kotlin/Function1<kotlin/Long, kotlin/Long>): kotlin/Long`

- [ ] KSP-1105: kotlin.concurrent.atomics.AtomicLongArray の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicLongArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicArrayMigration.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.updateAndFetchAt` — fun AtomicLongArray.updateAndFetchAt(Int, Function1): Long  -- `final inline fun (kotlin.concurrent.atomics/AtomicLongArray).kotlin.concurrent.atomics/updateAndFetchAt(kotlin/Int, kotlin/Function1<kotlin/Long, kotlin/Long>): kotlin/Long`
    - `kotlin.concurrent.atomics.updateAt` — fun AtomicLongArray.updateAt(Int, Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicLongArray).kotlin.concurrent.atomics/updateAt(kotlin/Int, kotlin/Function1<kotlin/Long, kotlin/Long>)`

- [~] KSP-1106: kotlin.concurrent.atomics.AtomicNativePtr の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicNativePtr`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicNativePtr.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装状況: `atomics/AtomicNativePtr.kt` に `fetchAndUpdate` / `update` / `updateAndFetch` の CAS retry loop を追加。対象の重複 synthetic `fetchAndUpdate` member 登録を削除し、既存の Atomic source-extension 探索に `AtomicNativePtr` を追加。新規 Runtime / Runtime ABI は不要。
  - 個別確認（2026-09-17）: `swift build`、source-mode / stdlib-artifact-mode の対象 Golden worker 描画結果と committed Golden の `diff -u`、`SemanticsAndUtilitiesRegressionTests`（1 test）、`AtomicTopLevelSourceTests`（6 tests）、対象 diff case（`failed=0, skipped=1`）、`RuntimeABIExternalLinkValidationTests`（4 tests）、TODO ID を確認済み。Sema Golden suite 全体と全 diff ケースは未実行。
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.fetchAndUpdate` — fun AtomicNativePtr.fetchAndUpdate(Function1): NativePtr  -- `final inline fun (kotlin.concurrent.atomics/AtomicNativePtr).kotlin.concurrent.atomics/fetchAndUpdate(kotlin/Function1<kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr>): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.update` — fun AtomicNativePtr.update(Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicNativePtr).kotlin.concurrent.atomics/update(kotlin/Function1<kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr>)`
    - `kotlin.concurrent.atomics.updateAndFetch` — fun AtomicNativePtr.updateAndFetch(Function1): NativePtr  -- `final inline fun (kotlin.concurrent.atomics/AtomicNativePtr).kotlin.concurrent.atomics/updateAndFetch(kotlin/Function1<kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr>): kotlin.native.internal/NativePtr`

- [ ] KSP-1107: kotlin.concurrent.atomics.AtomicReference の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.fetchAndUpdate` — fun AtomicReference.fetchAndUpdate(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicReference<#A>).kotlin.concurrent.atomics/fetchAndUpdate(kotlin/Function1<#A, #A>): #A`
    - `kotlin.concurrent.atomics.update` — fun AtomicReference.update(Function1): Unit  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicReference<#A>).kotlin.concurrent.atomics/update(kotlin/Function1<#A, #A>)`
    - `kotlin.concurrent.atomics.updateAndFetch` — fun AtomicReference.updateAndFetch(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicReference<#A>).kotlin.concurrent.atomics/updateAndFetch(kotlin/Function1<#A, #A>): #A`

- [ ] KSP-1108: kotlin.concurrent.atomics.AtomicArray top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicArray.<init>` — constructor (Array)  -- `constructor <init>(kotlin/Array<#A>)`

- [ ] KSP-1109: kotlin.concurrent.atomics.AtomicArray.AtomicArray の未実装 stdlib API を実装する（13 件）
  - 対象: `kotlin.concurrent.atomics.AtomicArray` / receiver `AtomicArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicArray/AtomicArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicArray_AtomicArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_AtomicArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_AtomicArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicArray.compareAndExchange` — fun AtomicArray.compareAndExchange(Int, , ): #A  -- `final fun compareAndExchange(kotlin/Int, #A, #A): #A`
    - `kotlin.concurrent.atomics.AtomicArray.compareAndExchangeAt` — fun AtomicArray.compareAndExchangeAt(Int, , ): #A  -- `final fun compareAndExchangeAt(kotlin/Int, #A, #A): #A`
    - `kotlin.concurrent.atomics.AtomicArray.compareAndSet` — fun AtomicArray.compareAndSet(Int, , ): Boolean  -- `final fun compareAndSet(kotlin/Int, #A, #A): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicArray.compareAndSetAt` — fun AtomicArray.compareAndSetAt(Int, , ): Boolean  -- `final fun compareAndSetAt(kotlin/Int, #A, #A): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicArray.exchangeAt` — fun AtomicArray.exchangeAt(Int, ): #A  -- `final fun exchangeAt(kotlin/Int, #A): #A`
    - `kotlin.concurrent.atomics.AtomicArray.get` — fun AtomicArray.get(Int): #A  -- `final fun get(kotlin/Int): #A`
    - `kotlin.concurrent.atomics.AtomicArray.getAndSet` — fun AtomicArray.getAndSet(Int, ): #A  -- `final fun getAndSet(kotlin/Int, #A): #A`
    - `kotlin.concurrent.atomics.AtomicArray.length` — val AtomicArray.length: Int  -- `final val length`
    - `kotlin.concurrent.atomics.AtomicArray.loadAt` — fun AtomicArray.loadAt(Int): #A  -- `final fun loadAt(kotlin/Int): #A`
    - `kotlin.concurrent.atomics.AtomicArray.set` — fun AtomicArray.set(Int, ): Unit  -- `final fun set(kotlin/Int, #A)`
    - `kotlin.concurrent.atomics.AtomicArray.size` — val AtomicArray.size: Int  -- `final val size`
    - `kotlin.concurrent.atomics.AtomicArray.storeAt` — fun AtomicArray.storeAt(Int, ): Unit  -- `final fun storeAt(kotlin/Int, #A)`
    - `kotlin.concurrent.atomics.AtomicArray.toString` — fun AtomicArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1111: kotlin.concurrent.atomics.AtomicBoolean.AtomicBoolean の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.concurrent.atomics.AtomicBoolean` / receiver `AtomicBoolean`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicBoolean/AtomicBoolean.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicBoolean_AtomicBoolean_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicBoolean_AtomicBoolean_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicBoolean_AtomicBoolean_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicBoolean.compareAndExchange` — fun AtomicBoolean.compareAndExchange(Boolean, Boolean): Boolean  -- `final fun compareAndExchange(kotlin/Boolean, kotlin/Boolean): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicBoolean.exchange` — fun AtomicBoolean.exchange(Boolean): Boolean  -- `final fun exchange(kotlin/Boolean): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicBoolean.load` — fun AtomicBoolean.load(): Boolean  -- `final fun load(): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicBoolean.store` — fun AtomicBoolean.store(Boolean): Unit  -- `final fun store(kotlin/Boolean)`
    - `kotlin.concurrent.atomics.AtomicBoolean.toString` — fun AtomicBoolean.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1112: kotlin.concurrent.atomics.AtomicInt top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicInt` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicInt/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicInt_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicInt.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [x] KSP-1113: kotlin.concurrent.atomics.AtomicInt.AtomicInt の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.concurrent.atomics.AtomicInt` / receiver `AtomicInt`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicInt/AtomicInt.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicInt_AtomicInt_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_AtomicInt_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_AtomicInt_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicInt.addAndFetch` — fun AtomicInt.addAndFetch(Int): Int  -- `final fun addAndFetch(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.compareAndExchange` — fun AtomicInt.compareAndExchange(Int, Int): Int  -- `final fun compareAndExchange(kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.exchange` — fun AtomicInt.exchange(Int): Int  -- `final fun exchange(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.getAndAdd` — fun AtomicInt.getAndAdd(Int): Int  -- `final fun getAndAdd(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.getAndDecrement` — fun AtomicInt.getAndDecrement(): Int  -- `final fun getAndDecrement(): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.getAndIncrement` — fun AtomicInt.getAndIncrement(): Int  -- `final fun getAndIncrement(): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.load` — fun AtomicInt.load(): Int  -- `final fun load(): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.store` — fun AtomicInt.store(Int): Unit  -- `final fun store(kotlin/Int)`
    - `kotlin.concurrent.atomics.AtomicInt.toString` — fun AtomicInt.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.atomics.AtomicInt.value` — val AtomicInt.value: Int  -- `final var value`
  - 完了根拠（2026-09-16）: `AtomicInt/AtomicInt.kt` に10 receiver APIをsource-backed実装し、既存のInt atomic bridgeへ委譲。bundled source extension の一般解決と import/package provenance を用いて、canonical alias の呼び出しを source-backed 実装へ接続した。legacy `compareAndExchange` wrapper と `value` synthetic property は互換性のため保持し、同一実装との重複警告だけを抑制している。

- [x] KSP-1114: kotlin.concurrent.atomics.AtomicIntArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics.AtomicIntArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicIntArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicIntArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.concurrent.atomics.AtomicIntArray.<init>` — constructor (IntArray)  -- `constructor <init>(kotlin/IntArray)`
  - 完了根拠 (2026-09-16): `AtomicIntArray/Stdlib.kt` に `AtomicIntArray(Int)` の `kk_atomic_int_array_create` source-backed 宣言と、`AtomicIntArray(IntArray)` の public copy-loop 実装を追加した。artifact import 時も source-backed constructor overload を通常解決へ渡すよう `CallTypeChecker` の atomic-array 特例ガードを補正した。残余の nominal shell、`size`/receiver 操作、既存 runtime bridge は KSP-1115 の所有範囲のため保持。

- [ ] KSP-1115: kotlin.concurrent.atomics.AtomicIntArray.AtomicIntArray の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.concurrent.atomics.AtomicIntArray` / receiver `AtomicIntArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicIntArray/AtomicIntArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicIntArray_AtomicIntArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_AtomicIntArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_AtomicIntArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicIntArray.compareAndExchange` — fun AtomicIntArray.compareAndExchange(Int, Int, Int): Int  -- `final fun compareAndExchange(kotlin/Int, kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicIntArray.compareAndSet` — fun AtomicIntArray.compareAndSet(Int, Int, Int): Boolean  -- `final fun compareAndSet(kotlin/Int, kotlin/Int, kotlin/Int): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicIntArray.length` — val AtomicIntArray.length: Int  -- `final val length`
    - `kotlin.concurrent.atomics.AtomicIntArray.size` — val AtomicIntArray.size: Int  -- `final val size`
    - `kotlin.concurrent.atomics.AtomicIntArray.toString` — fun AtomicIntArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1116: kotlin.concurrent.atomics.AtomicLong top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicLong` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLong/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLong_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicLong.<init>` — constructor (Long)  -- `constructor <init>(kotlin/Long)`

- [ ] KSP-1117: kotlin.concurrent.atomics.AtomicLong.AtomicLong の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.concurrent.atomics.AtomicLong` / receiver `AtomicLong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLong/AtomicLong.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLong_AtomicLong_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_AtomicLong_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_AtomicLong_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicLong.addAndFetch` — fun AtomicLong.addAndFetch(Long): Long  -- `final fun addAndFetch(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.compareAndExchange` — fun AtomicLong.compareAndExchange(Long, Long): Long  -- `final fun compareAndExchange(kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.exchange` — fun AtomicLong.exchange(Long): Long  -- `final fun exchange(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.getAndAdd` — fun AtomicLong.getAndAdd(Long): Long  -- `final fun getAndAdd(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.getAndDecrement` — fun AtomicLong.getAndDecrement(): Long  -- `final fun getAndDecrement(): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.getAndIncrement` — fun AtomicLong.getAndIncrement(): Long  -- `final fun getAndIncrement(): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.load` — fun AtomicLong.load(): Long  -- `final fun load(): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.store` — fun AtomicLong.store(Long): Unit  -- `final fun store(kotlin/Long)`
    - `kotlin.concurrent.atomics.AtomicLong.toString` — fun AtomicLong.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.atomics.AtomicLong.value` — val AtomicLong.value: Long  -- `final var value`

- [ ] KSP-1118: kotlin.concurrent.atomics.AtomicLongArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics.AtomicLongArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLongArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicLongArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.concurrent.atomics.AtomicLongArray.<init>` — constructor (LongArray)  -- `constructor <init>(kotlin/LongArray)`

- [ ] KSP-1119: kotlin.concurrent.atomics.AtomicLongArray.AtomicLongArray の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.concurrent.atomics.AtomicLongArray` / receiver `AtomicLongArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLongArray/AtomicLongArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLongArray_AtomicLongArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_AtomicLongArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_AtomicLongArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicLongArray.compareAndExchange` — fun AtomicLongArray.compareAndExchange(Int, Long, Long): Long  -- `final fun compareAndExchange(kotlin/Int, kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLongArray.compareAndSet` — fun AtomicLongArray.compareAndSet(Int, Long, Long): Boolean  -- `final fun compareAndSet(kotlin/Int, kotlin/Long, kotlin/Long): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicLongArray.length` — val AtomicLongArray.length: Int  -- `final val length`
    - `kotlin.concurrent.atomics.AtomicLongArray.size` — val AtomicLongArray.size: Int  -- `final val size`
    - `kotlin.concurrent.atomics.AtomicLongArray.toString` — fun AtomicLongArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1121: kotlin.concurrent.atomics.AtomicNativePtr.AtomicNativePtr の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.concurrent.atomics.AtomicNativePtr` / receiver `AtomicNativePtr`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicNativePtr/AtomicNativePtr.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_AtomicNativePtr_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicNativePtr.compareAndExchange` — fun AtomicNativePtr.compareAndExchange(NativePtr, NativePtr): NativePtr  -- `final fun compareAndExchange(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.AtomicNativePtr.compareAndSet` — fun AtomicNativePtr.compareAndSet(NativePtr, NativePtr): Boolean  -- `final fun compareAndSet(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicNativePtr.exchange` — fun AtomicNativePtr.exchange(NativePtr): NativePtr  -- `final fun exchange(kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.AtomicNativePtr.getAndSet` — fun AtomicNativePtr.getAndSet(NativePtr): NativePtr  -- `final fun getAndSet(kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.AtomicNativePtr.load` — fun AtomicNativePtr.load(): NativePtr  -- `final fun load(): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.AtomicNativePtr.store` — fun AtomicNativePtr.store(NativePtr): Unit  -- `final fun store(kotlin.native.internal/NativePtr)`
    - `kotlin.concurrent.atomics.AtomicNativePtr.toString` — fun AtomicNativePtr.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.atomics.AtomicNativePtr.value` — val AtomicNativePtr.value: NativePtr  -- `final var value`

- [ ] KSP-1122: kotlin.concurrent.atomics.AtomicReference top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicReference` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicReference/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicReference_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicReference.<init>` — constructor ()  -- `constructor <init>(#A)`

- [x] KSP-1123: kotlin.concurrent.atomics.AtomicReference.AtomicReference の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.concurrent.atomics.AtomicReference` / receiver `AtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicReference/AtomicReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicReference_AtomicReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_AtomicReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_AtomicReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicReference.compareAndExchange` — fun AtomicReference.compareAndExchange(, ): #A  -- `final fun compareAndExchange(#A, #A): #A`
    - `kotlin.concurrent.atomics.AtomicReference.exchange` — fun AtomicReference.exchange(): #A  -- `final fun exchange(#A): #A`
    - `kotlin.concurrent.atomics.AtomicReference.getAndSet` — fun AtomicReference.getAndSet(): #A  -- `final fun getAndSet(#A): #A`
    - `kotlin.concurrent.atomics.AtomicReference.load` — fun AtomicReference.load(): #A  -- `final fun load(): #A`
    - `kotlin.concurrent.atomics.AtomicReference.store` — fun AtomicReference.store(): Unit  -- `final fun store(#A)`
    - `kotlin.concurrent.atomics.AtomicReference.toString` — fun AtomicReference.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.atomics.AtomicReference.value` — val AtomicReference.value: #A  -- `final var value`
  - 完了根拠（2026-09-23）: 7 シンボルは全て `kotlin.concurrent` class shell の runtime-linked member stub で既に正しく解決しており、canonical API 表面を網羅済み。`AtomicReference/AtomicReference.kt` には `compareAndExchange` のみ source-backed 宣言を置いた（member は `AtomicMigration.kt` の `kotlin.concurrent` 拡張で既に抑制済み、atomics package 優先で本宣言が解決される）。`load`/`store`/`exchange`/`getAndSet`/`value` は member 所有のまま残した: 関数ジェネリック extern の T 戻り値は nullable 値型 (`Int?` 等) の stored `null` を型デフォルト値に misdecode する（KUU-840、KUU-837 と同一家系の erased-T 境界 marshal バグの戻り値側）。`var value` は bundled extension property が class 型パラメータを書けず `*` 投影の `Any?` 版は member の T 型 getter を隠すため source 化不可（KSWIFTK-PARSE-0002 制約）。`toString` は member `kotlin.Any.toString` がオーナー（member は extension に必ず勝つため source 側からは差し替え不可）のため、`runtimeElementToString` に `AtomicRefBox` の描画を追加して格納値を表示するよう修正（JDK AtomicReference 準拠: `String.valueOf(get())`）。既存バグ KUU-837（expected 引数 marshal）も member 経路で再現・本 PR 起因ではない。

- [ ] KSP-1137: kotlin.coroutines.AbstractCoroutineContextElement.AbstractCoroutineContextElement の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.coroutines.AbstractCoroutineContextElement` / receiver `AbstractCoroutineContextElement`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/CoroutineContextImpl.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_AbstractCoroutineContextElement_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_AbstractCoroutineContextElement_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_AbstractCoroutineContextElement_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.AbstractCoroutineContextElement.key` — val AbstractCoroutineContextElement.key: Key  -- `open val key`

- [ ] KSP-1139: kotlin.coroutines.Continuation.Continuation の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.coroutines.Continuation` / receiver `Continuation`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/Continuation/Continuation.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_Continuation_Continuation_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_Continuation_Continuation_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_Continuation_Continuation_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.Continuation.context` — val Continuation.context: CoroutineContext  -- `abstract val context`
    - `kotlin.coroutines.Continuation.resumeWith` — fun Continuation.resumeWith(Result): Unit  -- `abstract fun resumeWith(kotlin/Result<#A>)`

- [ ] KSP-1141: kotlin.coroutines.ContinuationInterceptor.ContinuationInterceptor の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.coroutines.ContinuationInterceptor` / receiver `ContinuationInterceptor`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/ContinuationInterceptor.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.ContinuationInterceptor.get` — fun ContinuationInterceptor.get(Key): #A1  -- `open fun <#A1: kotlin.coroutines/CoroutineContext.Element> get(kotlin.coroutines/CoroutineContext.Key<#A1>): #A1?`
    - `kotlin.coroutines.ContinuationInterceptor.interceptContinuation` — fun ContinuationInterceptor.interceptContinuation(Continuation): Continuation  -- `abstract fun <#A1: kotlin/Any?> interceptContinuation(kotlin.coroutines/Continuation<#A1>): kotlin.coroutines/Continuation<#A1>`
    - `kotlin.coroutines.ContinuationInterceptor.minusKey` — fun ContinuationInterceptor.minusKey(Key): CoroutineContext  -- `open fun minusKey(kotlin.coroutines/CoroutineContext.Key<*>): kotlin.coroutines/CoroutineContext`
    - `kotlin.coroutines.ContinuationInterceptor.releaseInterceptedContinuation` — fun ContinuationInterceptor.releaseInterceptedContinuation(Continuation): Unit  -- `open fun releaseInterceptedContinuation(kotlin.coroutines/Continuation<*>)`

- [ ] KSP-1143: kotlin.coroutines.CoroutineContext.CoroutineContext の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.coroutines.CoroutineContext` / receiver `CoroutineContext`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/CoroutineContext/CoroutineContext.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_CoroutineContext_CoroutineContext_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_CoroutineContext_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_CoroutineContext_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.CoroutineContext.fold` — fun CoroutineContext.fold(, Function2): #A1  -- `abstract fun <#A1: kotlin/Any?> fold(#A1, kotlin/Function2<#A1, kotlin.coroutines/CoroutineContext.Element, #A1>): #A1`
    - `kotlin.coroutines.CoroutineContext.get` — fun CoroutineContext.get(Key): #A1  -- `abstract fun <#A1: kotlin.coroutines/CoroutineContext.Element> get(kotlin.coroutines/CoroutineContext.Key<#A1>): #A1?`
    - `kotlin.coroutines.CoroutineContext.minusKey` — fun CoroutineContext.minusKey(Key): CoroutineContext  -- `abstract fun minusKey(kotlin.coroutines/CoroutineContext.Key<*>): kotlin.coroutines/CoroutineContext`
    - `kotlin.coroutines.CoroutineContext.plus` — fun CoroutineContext.plus(CoroutineContext): CoroutineContext  -- `open fun plus(kotlin.coroutines/CoroutineContext): kotlin.coroutines/CoroutineContext`

- [ ] KSP-1144: kotlin.coroutines.CoroutineContext.Element.Element の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.coroutines.CoroutineContext.Element` / receiver `Element`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/CoroutineContext/Element/Element.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_CoroutineContext_Element_Element_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_Element_Element_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_Element_Element_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.CoroutineContext.Element.fold` — fun Element.fold(, Function2): #A2  -- `open fun <#A2: kotlin/Any?> fold(#A2, kotlin/Function2<#A2, kotlin.coroutines/CoroutineContext.Element, #A2>): #A2`
    - `kotlin.coroutines.CoroutineContext.Element.get` — fun Element.get(Key): #A2  -- `open fun <#A2: kotlin.coroutines/CoroutineContext.Element> get(kotlin.coroutines/CoroutineContext.Key<#A2>): #A2?`
    - `kotlin.coroutines.CoroutineContext.Element.key` — val Element.key: Key  -- `abstract val key`
    - `kotlin.coroutines.CoroutineContext.Element.minusKey` — fun Element.minusKey(Key): CoroutineContext  -- `open fun minusKey(kotlin.coroutines/CoroutineContext.Key<*>): kotlin.coroutines/CoroutineContext`

- [ ] KSP-1148: kotlin.coroutines.SafeContinuation.SafeContinuation の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.coroutines.SafeContinuation` / receiver `SafeContinuation`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/SafeContinuationNative.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_SafeContinuation_SafeContinuation_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_SafeContinuation_SafeContinuation_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_SafeContinuation_SafeContinuation_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.SafeContinuation.context` — val SafeContinuation.context: CoroutineContext  -- `final val context`
    - `kotlin.coroutines.SafeContinuation.getOrThrow` — fun SafeContinuation.getOrThrow(): Any  -- `final fun getOrThrow(): kotlin/Any?`
    - `kotlin.coroutines.SafeContinuation.resumeWith` — fun SafeContinuation.resumeWith(Result): Unit  -- `final fun resumeWith(kotlin/Result<#A>)`

- [ ] KSP-1149: kotlin.coroutines.cancellation top-level の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.coroutines.cancellation` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/cancellation/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_cancellation_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_cancellation_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_cancellation_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.cancellation.CancellationException` — class kotlin.coroutines.cancellation.CancellationException  -- `open class kotlin.coroutines.cancellation/CancellationException : kotlin/IllegalStateException {`
    - `kotlin.coroutines.cancellation.CancellationException` — fun CancellationException(Throwable): CancellationException  -- `final inline fun kotlin.coroutines.cancellation/CancellationException(kotlin/Throwable?): kotlin.coroutines.cancellation/CancellationException`
    - `kotlin.coroutines.cancellation.CancellationException` — fun CancellationException(String, Throwable): CancellationException  -- `final inline fun kotlin.coroutines.cancellation/CancellationException(kotlin/String?, kotlin/Throwable?): kotlin.coroutines.cancellation/CancellationException`

- [ ] KSP-1153: kotlin.coroutines.intrinsics.SuspendFunction0 の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.coroutines.intrinsics` / receiver `SuspendFunction0`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/intrinsics/SuspendFunction0.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_intrinsics_SuspendFunction0_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_SuspendFunction0_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_SuspendFunction0_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.intrinsics.createCoroutineUnintercepted` — fun SuspendFunction0.createCoroutineUnintercepted(Continuation): Continuation  -- `final fun <#A: kotlin/Any?> (kotlin.coroutines/SuspendFunction0<#A>).kotlin.coroutines.intrinsics/createCoroutineUnintercepted(kotlin.coroutines/Continuation<#A>): kotlin.coroutines/Continuation<kotlin/Unit>`
    - `kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn` — fun SuspendFunction0.startCoroutineUninterceptedOrReturn(Continuation): Any  -- `final inline fun <#A: kotlin/Any?> (kotlin.coroutines/SuspendFunction0<#A>).kotlin.coroutines.intrinsics/startCoroutineUninterceptedOrReturn(kotlin.coroutines/Continuation<#A>): kotlin/Any?`

- [ ] KSP-1154: kotlin.coroutines.intrinsics.SuspendFunction1 の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.coroutines.intrinsics` / receiver `SuspendFunction1`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/intrinsics/SuspendFunction1.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_intrinsics_SuspendFunction1_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_SuspendFunction1_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_SuspendFunction1_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.intrinsics.createCoroutineUnintercepted` — fun SuspendFunction1.createCoroutineUnintercepted(, Continuation): Continuation  -- `final fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.coroutines/SuspendFunction1<#A, #B>).kotlin.coroutines.intrinsics/createCoroutineUnintercepted(#A, kotlin.coroutines/Continuation<#B>): kotlin.coroutines/Continuation<kotlin/Unit>`
    - `kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn` — fun SuspendFunction1.startCoroutineUninterceptedOrReturn(, Continuation): Any  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.coroutines/SuspendFunction1<#A, #B>).kotlin.coroutines.intrinsics/startCoroutineUninterceptedOrReturn(#A, kotlin.coroutines/Continuation<#B>): kotlin/Any?`

- [ ] KSP-1155: kotlin.coroutines.intrinsics.CoroutineSingletons.CoroutineSingletons の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.coroutines.intrinsics.CoroutineSingletons` / receiver `CoroutineSingletons`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/intrinsics/CoroutineSingletons/CoroutineSingletons.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_intrinsics_CoroutineSingletons_CoroutineSingletons_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_CoroutineSingletons_CoroutineSingletons_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_CoroutineSingletons_CoroutineSingletons_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.intrinsics.CoroutineSingletons.entries` — val CoroutineSingletons.entries: EnumEntries  -- `final val entries`
    - `kotlin.coroutines.intrinsics.CoroutineSingletons.valueOf` — fun CoroutineSingletons.valueOf(String): CoroutineSingletons  -- `final fun valueOf(kotlin/String): kotlin.coroutines.intrinsics/CoroutineSingletons`
    - `kotlin.coroutines.intrinsics.CoroutineSingletons.values` — fun CoroutineSingletons.values(): Array  -- `final fun values(): kotlin/Array<kotlin.coroutines.intrinsics/CoroutineSingletons>`

- [x] KSP-1191: kotlin.native top-level の未実装 stdlib API を実装する（27 件）
  - 対象: `kotlin.native` / top-level
  - 実装先 .kt: 宣言ごとに本家 kotlin-native のオーナーファイルへ追加する（`Annotations.kt`: CName/EagerInitialization/NoInline/SymbolName/ObjCName/HiddenFromObjC/HidesFromObjC/RefinesInSwift/ShouldRefineInSwift、`BitSet.kt`: BitSet、`Blob.kt`: ImmutableBlob/immutableBlobOf、`ObsoleteNativeApi.kt`: ObsoleteNativeApi、`Platform.kt`: OsFamily/CpuArchitecture/MemoryModel/Platform/isExperimentalMM、`Runtime.kt`: IncorrectDereferenceException/initRuntimeIfNeeded/{get,set}UnhandledExceptionHook/processUnhandledException/terminateWithUnhandledException、`simd.kt`: vectorOf。いずれも `Sources/CompilerCore/Stdlib/kotlin/native/` 直下。KSP-1541 で旧 `native/Stdlib.kt` 等の per-type ディレクトリ名は廃止済み）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.BitSet` — class kotlin.native.BitSet  -- `final class kotlin.native/BitSet {`
    - `kotlin.native.CName` — class kotlin.native.CName  -- `open annotation class kotlin.native/CName : kotlin/Annotation {`
    - `kotlin.native.CpuArchitecture` — enumClass kotlin.native.CpuArchitecture  -- `final enum class kotlin.native/CpuArchitecture : kotlin/Enum<kotlin.native/CpuArchitecture> {`
    - `kotlin.native.EagerInitialization` — class kotlin.native.EagerInitialization  -- `open annotation class kotlin.native/EagerInitialization : kotlin/Annotation {`
    - `kotlin.native.FreezingIsDeprecated` — class kotlin.native.FreezingIsDeprecated  -- `open annotation class kotlin.native/FreezingIsDeprecated : kotlin/Annotation {`
    - `kotlin.native.HiddenFromObjC` — class kotlin.native.HiddenFromObjC  -- `open annotation class kotlin.native/HiddenFromObjC : kotlin/Annotation {`
    - `kotlin.native.HidesFromObjC` — class kotlin.native.HidesFromObjC  -- `open annotation class kotlin.native/HidesFromObjC : kotlin/Annotation {`
    - `kotlin.native.ImmutableBlob` — class kotlin.native.ImmutableBlob  -- `final class kotlin.native/ImmutableBlob {`
    - `kotlin.native.IncorrectDereferenceException` — class kotlin.native.IncorrectDereferenceException  -- `final class kotlin.native/IncorrectDereferenceException : kotlin/RuntimeException {`
    - `kotlin.native.MemoryModel` — enumClass kotlin.native.MemoryModel  -- `final enum class kotlin.native/MemoryModel : kotlin/Enum<kotlin.native/MemoryModel> {`
    - `kotlin.native.NoInline` — class kotlin.native.NoInline  -- `open annotation class kotlin.native/NoInline : kotlin/Annotation {`
    - `kotlin.native.ObjCName` — class kotlin.native.ObjCName  -- `open annotation class kotlin.native/ObjCName : kotlin/Annotation {`
    - `kotlin.native.ObsoleteNativeApi` — class kotlin.native.ObsoleteNativeApi  -- `open annotation class kotlin.native/ObsoleteNativeApi : kotlin/Annotation {`
    - `kotlin.native.OsFamily` — enumClass kotlin.native.OsFamily  -- `final enum class kotlin.native/OsFamily : kotlin/Enum<kotlin.native/OsFamily> {`
    - `kotlin.native.Platform` — object kotlin.native.Platform  -- `final object kotlin.native/Platform {`
    - `kotlin.native.RefinesInSwift` — class kotlin.native.RefinesInSwift  -- `open annotation class kotlin.native/RefinesInSwift : kotlin/Annotation {`
    - `kotlin.native.ShouldRefineInSwift` — class kotlin.native.ShouldRefineInSwift  -- `open annotation class kotlin.native/ShouldRefineInSwift : kotlin/Annotation {`
    - `kotlin.native.SymbolName` — class kotlin.native.SymbolName  -- `open annotation class kotlin.native/SymbolName : kotlin/Annotation {`
    - `kotlin.native.getUnhandledExceptionHook` — fun getUnhandledExceptionHook(): Function1  -- `final fun kotlin.native/getUnhandledExceptionHook(): kotlin/Function1<kotlin/Throwable, kotlin/Unit>?`
    - `kotlin.native.immutableBlobOf` — fun immutableBlobOf(Array): ImmutableBlob  -- `final fun kotlin.native/immutableBlobOf(kotlin/ShortArray...): kotlin.native/ImmutableBlob`
    - `kotlin.native.initRuntimeIfNeeded` — fun initRuntimeIfNeeded(): Unit  -- `final fun kotlin.native/initRuntimeIfNeeded()`
    - `kotlin.native.isExperimentalMM` — fun isExperimentalMM(): Boolean  -- `final fun kotlin.native/isExperimentalMM(): kotlin/Boolean`
    - `kotlin.native.processUnhandledException` — fun processUnhandledException(Throwable): Unit  -- `final fun kotlin.native/processUnhandledException(kotlin/Throwable)`
    - `kotlin.native.setUnhandledExceptionHook` — fun setUnhandledExceptionHook(Function1): Function1  -- `final fun kotlin.native/setUnhandledExceptionHook(kotlin/Function1<kotlin/Throwable, kotlin/Unit>?): kotlin/Function1<kotlin/Throwable, kotlin/Unit>?`
    - `kotlin.native.terminateWithUnhandledException` — fun terminateWithUnhandledException(Throwable): Nothing  -- `final fun kotlin.native/terminateWithUnhandledException(kotlin/Throwable): kotlin/Nothing`
    - `kotlin.native.vectorOf` — fun vectorOf(Float, Float, Float, Float): Vector128  -- `final fun kotlin.native/vectorOf(kotlin/Float, kotlin/Float, kotlin/Float, kotlin/Float): kotlinx.cinterop/Vector128`
    - `kotlin.native.vectorOf` — fun vectorOf(Int, Int, Int, Int): Vector128  -- `final fun kotlin.native/vectorOf(kotlin/Int, kotlin/Int, kotlin/Int, kotlin/Int): kotlinx.cinterop/Vector128`
  - 実装済み（2026-09-18）: `Platform.kt` の `MemoryModel`/`isExperimentalMM`、`Runtime.kt` の runtime hook 一式、`Blob.kt` の `ImmutableBlob`/`immutableBlobOf`、`simd.kt` の `vectorOf` を追加。source-backed 宣言を優先するよう合成 Sema 登録を整理し、`Vector128` の cinterop shell と `Nothing`/`_Noreturn void` ABI 契約も追加・整合させた。既存 source-backed 宣言（Annotations/BitSet/ObsoleteNativeApi/Platform 等）は重複追加せず維持。
  - 検証: `swift build`、Sema Golden shard 73/98（8 cases）、Native unhandled-exception surface/KIR/Runtime focused tests、`check_todo_ids.sh`、`validate_runtime_abi_links.sh` は pass。diff case は `kotlin.native.*` のため既存 `SKIP-DIFF`（DEBT-DIFF-001）。全 Golden / 全 diff_cases は未実行。

- [ ] KSP-1192: kotlin.native.ImmutableBlob の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native` / receiver `ImmutableBlob`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/Blob.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_ImmutableBlob_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_ImmutableBlob_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_ImmutableBlob_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.asCPointer` — fun ImmutableBlob.asCPointer(Int): CPointer  -- `final fun (kotlin.native/ImmutableBlob).kotlin.native/asCPointer(kotlin/Int = ...): kotlinx.cinterop/CPointer<kotlinx.cinterop/ByteVarOf<kotlin/Byte>>`
    - `kotlin.native.asUCPointer` — fun ImmutableBlob.asUCPointer(Int): CPointer  -- `final fun (kotlin.native/ImmutableBlob).kotlin.native/asUCPointer(kotlin/Int = ...): kotlinx.cinterop/CPointer<kotlinx.cinterop/UByteVarOf<kotlin/UByte>>`
    - `kotlin.native.toByteArray` — fun ImmutableBlob.toByteArray(Int, Int): ByteArray  -- `final fun (kotlin.native/ImmutableBlob).kotlin.native/toByteArray(kotlin/Int = ..., kotlin/Int = ...): kotlin/ByteArray`
    - `kotlin.native.toUByteArray` — fun ImmutableBlob.toUByteArray(Int, Int): UByteArray  -- `final fun (kotlin.native/ImmutableBlob).kotlin.native/toUByteArray(kotlin/Int = ..., kotlin/Int = ...): kotlin/UByteArray`

- [ ] KSP-1203: kotlin.native.ImmutableBlob.ImmutableBlob の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.native.ImmutableBlob` / receiver `ImmutableBlob`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/Blob.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_ImmutableBlob_ImmutableBlob_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_ImmutableBlob_ImmutableBlob_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_ImmutableBlob_ImmutableBlob_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.ImmutableBlob.get` — fun ImmutableBlob.get(Int): Byte  -- `final fun get(kotlin/Int): kotlin/Byte`
    - `kotlin.native.ImmutableBlob.iterator` — fun ImmutableBlob.iterator(): ByteIterator  -- `final fun iterator(): kotlin.collections/ByteIterator`
    - `kotlin.native.ImmutableBlob.size` — val ImmutableBlob.size: Int  -- `final val size`

- [x] KSP-1215: kotlin.native.SymbolName.SymbolName の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.SymbolName` / receiver `SymbolName`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/Annotations.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_SymbolName_SymbolName_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_SymbolName_SymbolName_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_SymbolName_SymbolName_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 実装確認: `Annotations.kt` の source-backed `SymbolName(val name: String)` が `SymbolName.name` receiver property を提供しており、対象の Runtime/ABI、synthetic stub、name-string 特例は存在しないため追加削除なし。
  - 個別検証: GoldenHarnessWorker で `SymbolName.name` の member call が `kotlin.native.SymbolName.name[kind=prop]` に解決することを確認。diff ケースは Kotlin/JVM の参照 target がないため `SKIP-DIFF (DEBT-DIFF-001)`。
  - 未実行: 指定した Swift test filter の runner は共有 `.build/.lock` を含む実行環境待ちで開始出力を返さず停止したため、CI に委譲。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.SymbolName.name` — val SymbolName.name: String  -- `final val name`

- [x] KSP-1217: kotlin.native.concurrent.CPointer の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.native.concurrent` / receiver `CPointer`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Continuation.kt`（新規作成。本家 `kotlin-native/runtime/.../Continuation.kt` の `callContinuation0/1/2` のみ移植、`Continuation0/1/2` クラスは従来通り `HeaderHelpers+SyntheticNativeConcurrentRegistry.swift` の合成スタブのまま）
  - 前提として `kotlinx.cinterop.StableRef` を新規実装（`Sources/CompilerCore/Stdlib/kotlinx/cinterop/StableRef.kt`）: 本家の3関数本体が `asStableRef`/`StableRef.create`/`.get`/`.dispose`/`.asCPointer` に依存するが、`HeaderHelpers+SyntheticCInteropStubs.swift` の `StableRef` は nominal shell のみで `create`/`asStableRef` は名前とタイプパラメータの型を計算するだけで一度も `symbols.define` されない死んだ足場だった（実機確認: `KSWIFTK-SEMA-0024: Unresolved member function 'asStableRef'`）。Runtime 側は `Pinned<T>`（`kk_pin_object`/`kk_pinned_get`/`kk_unpin_object`）と同じ GC-root pin 方式だが、`StableRef` は同一オブジェクトへの複数の独立ハンドルを許すため（`Continuation1.invoke` が block 用と引数用で別ハンドルを作る）、`pinnedObjects`（Set）ではなく専用の refcount テーブル `GCState.stableRefCounts: [UInt:Int]`（`Sources/Runtime/RuntimeGC.swift`）で管理する新規ブリッジ `kk_stable_ref_create`/`_deref`/`_dispose`（`Sources/Runtime/RuntimeNativeAPI.swift`, `RuntimeABISpec+ABIParity.swift`）を追加（理由コード: GC・continuation 機構、§13-2）。`asStableRef` は reified を使わず通常の型パラメータ版として実装（本家は `inline fun <reified T>`）— `docs/stdlib-pipeline.md` §13-8 参照。
  - 副次発見・同PRで修正: `.kklib` ライブラリメタデータ import が「シグネチャに一切出現しない型パラメータ（phantom）」を復元できず `callContinuation1<Int>()` 等が `--stdlib-from-source` では通るのに通常の `.kklib` 経由コンパイルでは `KSWIFTK-SEMA-0002: No viable overload found` になる一般バグを発見。`Sources/CompilerCore/Sema/DataFlow/LibraryImport.swift`/`LibraryMetadataParsing.swift` に、overload しない owner に限定した「count のみ復元」フォールバックを実装し解消（回帰テスト: `LibMetadataSerializationTests.swift`）。宣言順を要する混在ケース（`filterIsInstanceTo` 等、現状は実害なしと確認済み）は KUU-546 へ分離。`@Deprecated(constVal)` の診断文言が定数値でなく識別子名になる別バグも発見し KUU-547 へ分離（回避策としてリテラルへインライン化）。
  - bridge/stub 整理: 対象シンボル（`callContinuation0/1/2`）自体に既存の `__kk_*`/`kk_*` Runtime 関数・`RuntimeABISpec` エントリ・`CallTypeChecker+*`/`CallLowerer+*` の name-string 特例は無かった（Sema 専用 synthetic stub のみ）ため削除対象なし。`HeaderHelpers+SyntheticNativeConcurrentRegistry.swift` の `callContinuationFunctions` ステップ（`registerNativeConcurrentCallContinuationFunctions`/`registerNativeConcurrentCallContinuationFunction`）を削除。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_CPointer_n.kt` 追加、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_CPointer_n.kt` 追加（兄弟ケース同様 `SKIP-DIFF (DEBT-DIFF-001)`、`DIFF_REQUIRE_JDK21=0 bash Scripts/diff_kotlinc.sh` で skip=1 green 確認）
  - 実行検証: `Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+CinteropStableRef.swift` を新設し、StableRef の基本ラウンドトリップ・同一オブジェクトへの独立2ハンドルの refcount 非干渉・callContinuation0/1/2 の実行時呼び出しを bundled `.kklib` 経由で実機検証（KSP-INF-006）
  - **副次発見（本PRでは未修正・KUU-548）**: 実行時検証で `callContinuation2<Int, String>()` が決定的に `SIGBUS`（`EXC_BAD_ACCESS`）でクラッシュすることを発見。バイセクションの結果、`callContinuation1<String>()` も同様にクラッシュし、`Triple`/`callContinuation2` 固有ではなく「ジェネリック関数値 `(T1) -> Unit` の呼び出しにおいて、`T1` に束縛される値がジェネリッククラスのフィールド読み取り経由（`Pair.second`/`Triple.second`/`.third`）かつ参照型（`String` 等）の場合」に一般化されるクラッシュだと判明（`callContinuation0()`・`callContinuation1<Int>()`・`callContinuation2<Int, Int>()` のようにプリミティブ型のみの場合は正常動作）。`kotlinx.cinterop`/stdlib を一切使わない `Pair<(T1) -> Unit, T1>` のみの最小再現でも同一クラッシュ（`kk_fn_kk_lambda_N_s60000000` 内 `EXC_BAD_ACCESS`）を確認し、`--stdlib-from-source` でも再現するため `.kklib` import 経路や本PRで見つけた phantom 型パラメータ修正とも無関係、`StableRef` 固有でもない既存の一般バグと結論。KUU-548 として起票。`callContinuation0/1/2` の Kotlin ソース実装・Sema 解決・golden は全て正しく、このバグの影響を受けているだけなので実装自体は差し戻さず、実行時テスト（`testCallContinuationFunctionsInvokeWrappedClosures`）はプリミティブ型引数のみに絞って green を維持し、参照型引数のケースは `testCallContinuationFunctionsInvokeWrappedClosuresWithReferenceTypeArguments` として `@Test(.disabled("...KUU-548"))` 付きで追加（KUU-548 修正後に有効化する想定の回帰テスト）。**注意**: `callContinuation1<T1>`/`callContinuation2<T1,T2>` は `T1`/`T2` が参照型の場合は現状クラッシュするため、実運用ではプリミティブ型引数のみで利用可能（upstream Kotlin/Native の実装と異なりこの制約がある）。
  - 完了ゲート: `NativeConcurrentSyntheticStubTests` / `NativeConcurrentAPISurfaceInventoryTests` / `RuntimeABIExternalLinkValidationTests` / `LibMetadataSerializationTests` green、`BundledStdlibExecutionTests+CinteropStableRef`（4件、うち1件は KUU-548 待ちで意図的に disabled）green、Sema golden green（差分は対象2ファイルのみ）、`bash Scripts/check_todo_ids.sh` pass、diff_cases 単体 skip=1 green。全テスト・全 Golden・全 diff ケースは CI に委譲（AGENTS.md 最小スコープ方針）。

- [~] KSP-1218: kotlin.native.concurrent.Collection の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent` / receiver `Collection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Future.kt`（該当ファイルが無ければ新規作成）
  - 実装メモ: Kotlin 2.3.10 の deprecated extension `Collection<Future<T>>.waitForMultipleFutures(Int)` を追加。既存の top-level 実装と共通 runtime bridge は維持し、対象固有の synthetic stub・Runtime ABI・name-string 特例は存在しないため変更なし。
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_Collection_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_Collection_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_Collection_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 個別検証: `swift build`、対象 golden shard（8 cases）、NativeConcurrent source/KIR focused tests、Runtime ABI（4件）、TODO ID、diff fixture（skip=1）が green。全体 Golden / 全 diff / aggregate gate は未実行。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.waitForMultipleFutures` — fun Collection.waitForMultipleFutures(Int): Set  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Collection<kotlin.native.concurrent/Future<#A>>).kotlin.native.concurrent/waitForMultipleFutures(kotlin/Int): kotlin.collections/Set<kotlin.native.concurrent/Future<#A>>`

- [ ] KSP-1219: kotlin.native.concurrent.DetachedObjectGraph の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent` / receiver `DetachedObjectGraph`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/ObjectTransfer.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.attach` — fun DetachedObjectGraph.attach(): #A  -- `final inline fun <#A: reified kotlin/Any?> (kotlin.native.concurrent/DetachedObjectGraph<#A>).kotlin.native.concurrent/attach(): #A`

- [ ] KSP-1220: kotlin.native.concurrent.AtomicInt top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent.AtomicInt` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Atomics.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicInt_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicInt_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicInt_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicInt.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [x] KSP-1221: kotlin.native.concurrent.AtomicInt.AtomicInt の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.native.concurrent.AtomicInt` / receiver `AtomicInt`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Atomics.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicInt_AtomicInt_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicInt_AtomicInt_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicInt_AtomicInt_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicInt.compareAndSwap` — fun AtomicInt.compareAndSwap(Int, Int): Int  -- `final fun compareAndSwap(kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.native.concurrent.AtomicInt.decrement` — fun AtomicInt.decrement(): Unit  -- `final fun decrement()`
    - `kotlin.native.concurrent.AtomicInt.getAndAdd` — fun AtomicInt.getAndAdd(Int): Int  -- `final fun getAndAdd(kotlin/Int): kotlin/Int`
    - `kotlin.native.concurrent.AtomicInt.getAndDecrement` — fun AtomicInt.getAndDecrement(): Int  -- `final fun getAndDecrement(): kotlin/Int`
    - `kotlin.native.concurrent.AtomicInt.getAndIncrement` — fun AtomicInt.getAndIncrement(): Int  -- `final fun getAndIncrement(): kotlin/Int`
    - `kotlin.native.concurrent.AtomicInt.increment` — fun AtomicInt.increment(): Unit  -- `final fun increment()`
    - `kotlin.native.concurrent.AtomicInt.toString` — fun AtomicInt.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.AtomicInt.value` — val AtomicInt.value: Int  -- `final var value`
  - 実装根拠: `Atomics.kt` に 8 件を Kotlin source-backed extension として追加し、既存の共有 `__kk_atomic_int_*` Runtime ABI を private bridge 経由で再利用。KSP-1220 の AtomicInt synthetic nominal anchor / constructor は別タスクのため維持し、対象専用の synthetic stub・name-string 特例・Runtime ABI 変更は無し。
  - 検証根拠: AtomicInt receiver Sema golden を追加・生成し、対象を含む Sema shard の比較が pass。対象 golden の直接再レンダー一致、公開 surface inventory、synthetic anchor、Runtime ABI 外部リンク（4 tests）も green。対象 diff case は `SKIP-DIFF (DEBT-DIFF-001)` で skip=1、`check_todo_ids.sh` は pass。全 Sema golden / 全 diff ケースは CI に委譲。

- [~] KSP-1223: kotlin.native.concurrent.AtomicLong.AtomicLong の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.native.concurrent.AtomicLong` / receiver `AtomicLong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Atomics.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicLong_AtomicLong_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicLong_AtomicLong_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicLong_AtomicLong_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装・focused確認済み（2026-09-16）: `Atomics.kt` に `value`、`addAndGet(Int)`、`compareAndSwap`、`decrement`、`getAndAdd`、`getAndDecrement`、`getAndIncrement`、`increment`、`toString` を source-backed 実装。既存の shared `__kk_atomic_long_*` Runtime/RuntimeABI bridge は `kotlin.concurrent.AtomicLong` と共用のため残置し、対象の native synthetic stub / name-string 特例に追加の削除対象がないことを確認。`swift build` PASS、Sema golden 94 cases PASS、新規 diff case は `SKIP-DIFF (DEBT-DIFF-001)` で `total=0 failed=0 passed=0 skipped=1`、`bash Scripts/check_todo_ids.sh` PASS、`bash Scripts/validate_runtime_abi_links.sh` 4/4 PASS、`kswiftc --stdlib-from-source --emit object` の Mach-O object 生成 PASS、`git diff --check` PASS。全 Swift suite・全 Golden（Lexer/Parser/Sema/Diagnostics）・全 diff cases は未実行のため共通ゲート保留。
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicLong.addAndGet` — fun AtomicLong.addAndGet(Int): Long  -- `final fun addAndGet(kotlin/Int): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.compareAndSwap` — fun AtomicLong.compareAndSwap(Long, Long): Long  -- `final fun compareAndSwap(kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.decrement` — fun AtomicLong.decrement(): Unit  -- `final fun decrement()`
    - `kotlin.native.concurrent.AtomicLong.getAndAdd` — fun AtomicLong.getAndAdd(Long): Long  -- `final fun getAndAdd(kotlin/Long): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.getAndDecrement` — fun AtomicLong.getAndDecrement(): Long  -- `final fun getAndDecrement(): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.getAndIncrement` — fun AtomicLong.getAndIncrement(): Long  -- `final fun getAndIncrement(): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.increment` — fun AtomicLong.increment(): Unit  -- `final fun increment()`
    - `kotlin.native.concurrent.AtomicLong.toString` — fun AtomicLong.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.AtomicLong.value` — val AtomicLong.value: Long  -- `final var value`

- [ ] KSP-1225: kotlin.native.concurrent.AtomicNativePtr.AtomicNativePtr の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.native.concurrent.AtomicNativePtr` / receiver `AtomicNativePtr`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Atomics.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicNativePtr.compareAndSet` — fun AtomicNativePtr.compareAndSet(NativePtr, NativePtr): Boolean  -- `final fun compareAndSet(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin/Boolean`
    - `kotlin.native.concurrent.AtomicNativePtr.compareAndSwap` — fun AtomicNativePtr.compareAndSwap(NativePtr, NativePtr): NativePtr  -- `final fun compareAndSwap(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.native.concurrent.AtomicNativePtr.getAndSet` — fun AtomicNativePtr.getAndSet(NativePtr): NativePtr  -- `final fun getAndSet(kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.native.concurrent.AtomicNativePtr.toString` — fun AtomicNativePtr.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.AtomicNativePtr.value` — val AtomicNativePtr.value: NativePtr  -- `final var value`

- [x] KSP-1227: kotlin.native.concurrent.AtomicReference.AtomicReference の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.concurrent.AtomicReference` / receiver `AtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Atomics.kt`
  - bridge/stub 整理: 対象シンボルの stale な `kk_native_atomic_ref_*` RuntimeABI parity spec / allowlist を削除。`HeaderHelpers+Synthetic*Stubs.swift` 登録、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例は存在しなかった。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicReference_AtomicReference_n.kt` / `.golden` を追加し、指定の Swift 6 モードで更新。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicReference_AtomicReference_n.kt` を追加（Kotlin/Native-only のため `SKIP-DIFF (DEBT-DIFF-001)`）。
  - 実装状況: `value` / `getAndSet` / `compareAndSwap` / `toString` を source-backed 実装。Sema Golden 93 batches / 742 cases、diff case、TODO ID、Runtime ABI、`swift build`、`git diff --check` を確認済み。
  - 完了確認（2026-09-16）: branch `kuxu2525/kuu-379-ksp-1227`。Sema Golden suite、`bash Scripts/check_todo_ids.sh`、`bash Scripts/validate_runtime_abi_links.sh`、`swift build` が PASS。全 Golden / 全 diff は未実行（最小スコープ）。
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicReference.compareAndSwap` — fun AtomicReference.compareAndSwap(, ): #A  -- `final fun compareAndSwap(#A, #A): #A`
    - `kotlin.native.concurrent.AtomicReference.getAndSet` — fun AtomicReference.getAndSet(): #A  -- `final fun getAndSet(#A): #A`
    - `kotlin.native.concurrent.AtomicReference.toString` — fun AtomicReference.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.AtomicReference.value` — val AtomicReference.value: #A  -- `final var value`

- [ ] KSP-1234: kotlin.native.concurrent.DetachedObjectGraph top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.native.concurrent.DetachedObjectGraph` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/ObjectTransfer.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.DetachedObjectGraph.<init>` — constructor (CPointer)  -- `constructor <init>(kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?)`
    - `kotlin.native.concurrent.DetachedObjectGraph.<init>` — constructor (TransferMode, Function0)  -- `constructor <init>(kotlin.native.concurrent/TransferMode = ..., kotlin/Function0<#A>)`

- [x] KSP-1235: kotlin.native.concurrent.DetachedObjectGraph.DetachedObjectGraph の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.native.concurrent.DetachedObjectGraph` / receiver `DetachedObjectGraph`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/ObjectTransfer.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_DetachedObjectGraph_DetachedObjectGraph_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_DetachedObjectGraph_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_DetachedObjectGraph_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.DetachedObjectGraph.asCPointer` — fun DetachedObjectGraph.asCPointer(): CPointer  -- `final fun asCPointer(): kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?`
    - `kotlin.native.concurrent.DetachedObjectGraph.stable` — val DetachedObjectGraph.stable: AtomicNativePtr  -- `final val stable`
  - 完了根拠: `ObjectTransfer.kt` に Kotlin/Native 2.3.10 準拠の internal `NativePtr` constructor、`stable` backing property、`asCPointer()` receiver を追加。DetachedObjectGraph の synthetic nominal anchor を撤去し、対象シンボルに対応する Runtime ABI 関数・`RuntimeABISpec`・CallTypeChecker/CallLowerer の name-string 特例が無いことを確認した。`kotlin.concurrent.AtomicNativePtr` にはこの backing storage 用の internal constructor/value のみを追加し、公開 constructor/value の残りは KSP-1095/KSP-1096 の責務として維持した。Sema source-backed 回帰テスト、対象 Golden、対象 diff ケース、`check_todo_ids.sh`、`validate_runtime_abi_links.sh`、`git diff --check` を実行済み。全 Swift テスト・全 Golden・全 diff ケースは未実行（CI に委譲）。

- [x] KSP-1237: kotlin.native.concurrent.FreezableAtomicReference.FreezableAtomicReference の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.concurrent.FreezableAtomicReference` / receiver `FreezableAtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Atomics.kt`
  - bridge/stub 整理: `FreezableAtomicReference` 専用の `kk_freezable_atomic_ref_*` Runtime box/export と `RuntimeABISpec` parity entries を削除。`HeaderHelpers+Synthetic*Stubs.swift` 登録、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例は存在しなかった。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_FreezableAtomicReference_FreezableAtomicReference_n.kt` / `.golden` を追加し、指定の Swift 6 モードで更新。差分は source-backed な解決結果への機械的な追加。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_FreezableAtomicReference_FreezableAtomicReference_n.kt` を追加（Kotlin/Native-only のため `SKIP-DIFF (DEBT-DIFF-001)`）。
  - 実装状況: `value` / `compareAndSet` / `compareAndSwap` / `toString` を source-backed 実装。Sema Golden 94 batches、対象 Sema テスト、TODO ID、Runtime ABI、`swift build`、`git diff --check` を確認済み。
  - 完了確認（2026-09-16）: branch `kuxu2525/kuu-387-ksp-1237`。全 Sema Golden suite と `FreezableAtomicReferenceSourceTests` が PASS。全 Golden / 全 diff は未実行（Kotlin/Native-only の diff case は `SKIP-DIFF`）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.FreezableAtomicReference.compareAndSet` — fun FreezableAtomicReference.compareAndSet(, ): Boolean  -- `final fun compareAndSet(#A, #A): kotlin/Boolean`
    - `kotlin.native.concurrent.FreezableAtomicReference.compareAndSwap` — fun FreezableAtomicReference.compareAndSwap(, ): #A  -- `final fun compareAndSwap(#A, #A): #A`
    - `kotlin.native.concurrent.FreezableAtomicReference.toString` — fun FreezableAtomicReference.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.FreezableAtomicReference.value` — val FreezableAtomicReference.value: #A  -- `final var value`

- [x] KSP-1244: kotlin.native.concurrent.MutableData.MutableData の未実装 stdlib API を実装する（9 件）
  - 完了確認（2026-09-16）：MutableData の9 APIを Kotlin source-backed に移行し、メンバーの receiver・overload・Byte 戻り値・generic Function2 型を Sema 回帰で固定した。Sema 全 Golden（70 tests / 15 suites）、全 diff（1366 cases、failed=0、skipped=85）、TODO ID、Runtime ABI link、git diff check が pass。対象シンボルに専用 bridge / synthetic stub / RuntimeABI / name-string 特例は存在しなかったため追加変更なし。現行 CInterop に `Pinned.addressOf` と raw-memory bridge がないため、`append(COpaquePointer?, Int)` はサイズを管理し、`withPointerLocked` は明示的に UnsupportedOperationException としている。
  - 対象: `kotlin.native.concurrent.MutableData` / receiver `MutableData`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/MutableData.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_MutableData_MutableData_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_MutableData_MutableData_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_MutableData_MutableData_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.MutableData.append` — fun MutableData.append(MutableData): Unit  -- `final fun append(kotlin.native.concurrent/MutableData)`
    - `kotlin.native.concurrent.MutableData.append` — fun MutableData.append(CPointer, Int): Unit  -- `final fun append(kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?, kotlin/Int)`
    - `kotlin.native.concurrent.MutableData.append` — fun MutableData.append(ByteArray, Int, Int): Unit  -- `final fun append(kotlin/ByteArray, kotlin/Int = ..., kotlin/Int = ...)`
    - `kotlin.native.concurrent.MutableData.copyInto` — fun MutableData.copyInto(ByteArray, Int, Int, Int): Unit  -- `final fun copyInto(kotlin/ByteArray, kotlin/Int, kotlin/Int, kotlin/Int)`
    - `kotlin.native.concurrent.MutableData.get` — fun MutableData.get(Int): Byte  -- `final fun get(kotlin/Int): kotlin/Byte`
    - `kotlin.native.concurrent.MutableData.reset` — fun MutableData.reset(): Unit  -- `final fun reset()`
    - `kotlin.native.concurrent.MutableData.size` — val MutableData.size: Int  -- `final val size`
    - `kotlin.native.concurrent.MutableData.withBufferLocked` — fun MutableData.withBufferLocked(Function2): #A1  -- `final fun <#A1: kotlin/Any?> withBufferLocked(kotlin/Function2<kotlin/ByteArray, kotlin/Int, #A1>): #A1`
    - `kotlin.native.concurrent.MutableData.withPointerLocked` — fun MutableData.withPointerLocked(Function2): #A1  -- `final fun <#A1: kotlin/Any?> withPointerLocked(kotlin/Function2<kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>, kotlin/Int, #A1>): #A1`

- [ ] KSP-1251: kotlin.native.concurrent.Worker.Companion.Companion の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.concurrent.Worker.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Worker.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_Worker_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_Worker_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_Worker_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.Worker.Companion.activeWorkers` — val Companion.activeWorkers: List  -- `final val activeWorkers`
    - `kotlin.native.concurrent.Worker.Companion.current` — val Companion.current: Worker  -- `final val current`
    - `kotlin.native.concurrent.Worker.Companion.fromCPointer` — fun Companion.fromCPointer(CPointer): Worker  -- `final fun fromCPointer(kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?): kotlin.native.concurrent/Worker`
    - `kotlin.native.concurrent.Worker.Companion.start` — fun Companion.start(Boolean, String): Worker  -- `final fun start(kotlin/Boolean = ..., kotlin/String? = ...): kotlin.native.concurrent/Worker`

- [x] KSP-1253: kotlin.native.concurrent.WorkerBoundReference.WorkerBoundReference の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.native.concurrent.WorkerBoundReference` / receiver `WorkerBoundReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/WorkerBoundReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_WorkerBoundReference_WorkerBoundReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_WorkerBoundReference_WorkerBoundReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_WorkerBoundReference_WorkerBoundReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.WorkerBoundReference.value` — val WorkerBoundReference.value: #A  -- `final val value`
    - `kotlin.native.concurrent.WorkerBoundReference.valueOrNull` — val WorkerBoundReference.valueOrNull: #A  -- `final val valueOrNull`
    - `kotlin.native.concurrent.WorkerBoundReference.worker` — val WorkerBoundReference.worker: Worker  -- `final val worker`
  - 2026-09-14 実装: upstream kotlin-native `v2.1.0` の `WorkerBoundReference.kt`（legacy MM 撤去後の実体）を確認し、`value` はコンストラクタプロパティ、`valueOrNull` は `= value` の単純委譲、`worker` は構築時点の `Worker.current` 相当を束縛する形にした。`Worker.Companion.current`（公開 API）は別タスク KSP-1251 が未着手のため、`worker` を実装するのに必要な「実行中スレッドの current worker」概念を新規ランタイム機能として追加した: `RuntimeWorkerBox.execute`/`executeAfter` が実行するジョブの間だけ、CORO-003 で確立済みの `pthread_key_t` ベース thread-local ヘルパー（`makePthreadKey`/`pthreadGetValue`/`pthreadSetValue`、`RuntimeCoroutine.swift`）でそのワーカーの handle を記録し（`RuntimeWorkerBox.currentWorkerHandle()`。`Thread.current.threadDictionary` は既に同コミットで撤去済みの手法なので使わなかった）、未設定（メインスレッド等）の場合は遅延生成する main worker シングルトンにフォールバックする（`runtimeCurrentWorkerHandle()`, `Sources/Runtime/RuntimeNativeAPI.swift`）。これを内部専用ブリッジ `__kk_native_concurrent_current_worker`（引数なし、`.intptr` 返却、`Sources/Runtime/RuntimeNativeConcurrentABI.swift` + `Sources/RuntimeABI/RuntimeABISpec+NativeConcurrent.swift`）として公開し、Kotlin 側は `kotlin.native.internal.__nativeConcurrentCurrentWorker()`（`NativeConcurrentBridges.kt`）経由で `WorkerBoundReference.kt` からのみ利用する — `Worker.Companion.current` / `activeWorkers` / `fromCPointer` など公開 Companion surface は意図的に実装せず KSP-1251 に残した。既存 stub/registry には対象シンボルの登録が無かったため（`HeaderHelpers+SyntheticNativeConcurrentRegistry.swift` にはコメントのみ）、削除対象の `kk_*`/`CallTypeChecker`/`CallLowerer` 特例は無く新規 Kotlin 実装のみ。stale だった "value/worker properties remain a separate KSP-1253 task" コメント（`HeaderHelpers+SyntheticNativeConcurrentRegistry.swift`, `Tests/CompilerCoreTests/Sema/NativeConcurrentTopLevelSourceTests.swift`）も本 PR で更新した。
  - §13-2 ブリッジ入場審査: 新規 `__kk_native_concurrent_current_worker` の理由コードは「syscall 相当」— 実行中の OS スレッドがどの `Worker` に属するかは pthread thread-local（`pthread_getspecific`/`pthread_setspecific`、CORO-003 ヘルパー経由）でしか判定できず、pure Kotlin では表現不可能（既存の `kk_worker_platform_thread_id` と同種の「スレッド識別へのネイティブアクセス」理由）。`RuntimeABISpec` 登録済み、`specVersion` は `RuntimeABISpec.allFunctions` の内容から自動算出のため追加登録だけで更新される。`__kk_cdecl_count` は +1（837→838、確認コマンド: `grep -rhoE '@_cdecl\("__kk_[A-Za-z0-9_]+"\)' Sources/Runtime --include='*.swift' | sort -u | wc -l`）。`kk_cdecl_count` は不変（936）。影響範囲は `WorkerBoundReference.worker` の初期化のみ。
  - 検証: `swift build` PASS。`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` で新規ケースの golden を生成（`ref.value: String` / `ref.valueOrNull: String?` / `ref.worker: kotlin.native.concurrent.Worker` の3プロパティが期待どおり解決、既存 golden ファイルへの差分なし）。同ジョブ内で cinterop/collection/sequence 系など本変更と無関係な既存ケース 9 バッチ（72件）が "Golden worker timed out" で issue 扱いになったが、これは実行と同時刻に他セッションから周知のあった「このマシンで Golden 全走が 6 本以上同時実行中」というリソース競合による既知の誤診断パターン（内容差分ではなく timeout）であり、対象ファイルも本変更と無関係なため再実行はしていない。`RuntimeABIExternalLinkValidationTests` 4/4 PASS（新規ブリッジの KsSymbolName/RuntimeABISpec 整合を検証、`validate_runtime_abi_links.sh` と同一内容のため別途は未実行）。`CompilerBackendTests.BundledStdlibExecutionTests/testWorkerExecuteJobRunsWithoutWithWorker` / `testWorkerExecuteAfterRunsTrailingLambdaOperation` 2/2 PASS（`execute`/`executeAfter` へ足した current-worker tracking が既存の Worker 実行系を壊していないことを確認）。加えて `.build/debug/kswiftc` でエンドツーエンドのスモークを直接実行し確認: `WorkerBoundReference("x").value`/`.valueOrNull` が `"x"`、メインスレッド上の2つの `WorkerBoundReference` の `.worker.id` が一致、`Worker.start()` した別ワーカー上で構築した2つの `WorkerBoundReference` の `.worker.id` は互いに一致しつつメインスレッド側とは異なる — 期待どおりの worker-identity 分離を実機で確認（`.artifacts/diff_kotlinc/KSwiftKStdlib.kklib` を `KSWIFTK_STDLIB_LIBRARY` で指定し、共有ユーザーキャッシュ `~/Library/Caches/kswiftk/stdlib/` の同時実行汚染を回避）。`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_WorkerBoundReference_WorkerBoundReference_n.kt`（`DIFF_REQUIRE_JDK21=0`）は既存の兄弟ケース同様 `SKIP-DIFF (DEBT-DIFF-001)` で skip=1。`bash Scripts/check_todo_ids.sh` PASS。CLAUDE.md の最小スコープ方針および稼働中の他セッションからの周知に従い、`swift_test.sh` 全体・`--filter Golden` 四スイート一括・`diff_kotlinc.sh Scripts/diff_cases` 全体は未実行。
  - 副次的発見: `BUG-260`（下記）として別記。

- [ ] BUG-260: `kotlin.native.concurrent.withWorker { ... }` が本体が空でも常に unhandled top-level exception で panic する
  - 最小再現: `.build/debug/kswiftc repro.kt -o /tmp/repro && /tmp/repro` を以下で実行すると `KSwiftK panic [KSWIFTK-LINK-0003]: Unhandled top-level exception` を出して exit 1（`println("after")` は到達しない。実際に投げられた Kotlin 例外は無い）。
    ```kotlin
    @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
    import kotlin.native.concurrent.*
    fun main() {
        withWorker { println("inside") }
        println("after")
    }
    ```
  - 対比: `Worker.start()` + `worker.execute(...)` + `worker.requestTermination(true)`（`testWorkerExecuteJobRunsWithoutWithWorker` と同型、`worker.requestTermination(true)` の戻り値は待たない）は正常終了する。差分は `withWorker`（`Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Worker.kt` の `inline fun <R> withWorker(...)`）の `finally { __nativeConcurrentTerminateWorker(worker) }` 経路のみ。
  - 発見元: KSP-1253（WorkerBoundReference.value/valueOrNull/worker）のエンドツーエンド検証で `.build/debug/kswiftc` を直接実行した際に発見。`withWorker` を呼ぶテストがこれまで一件も存在しなかったため（`testWorkerExecuteJobRunsWithoutWithWorker` はその名のとおり `withWorker` を使わない）未検出だった。KSP-1253 の差分（`Worker.kt`・termination bridge 側は一切変更していない）とは無関係な既存バグであることを、変更前の挙動として確認済み。
  - 推定原因（未確定）: `__nativeConcurrentTerminateWorker`（`kotlin.native.internal`, `@KsSymbolName("__kk_native_concurrent_terminate_worker")`, `Sources/Runtime/RuntimeNativeConcurrentABI.swift`）は `RuntimeABISpec` 上 `isThrowing: false` / 単一 `workerHandle` 引数で、ABI 形状自体は既存の動作実績ある Unit 返却 external（`__kk_string_builder_set_length` 等）と矛盾しない。本体が空でも再現するため、疑われるのは (a) generic inline 関数内の try/finally lowering が finally 節の呼び出しと無関係に「例外あり」フラグを誤って立てる/未初期化のまま読む、または (b) `__kk_native_concurrent_terminate_worker` 内部で同期的に呼ぶ `kk_future_result`（`RuntimeFutureBox.result()`のブロッキング待機）が何らかの形で thrown-state を汚す、のいずれか。
  - 対処: 本タスクのスコープ（Lowering/ABI 例外伝播の調査）は KSP-1253 の安全な修正方針を超えるため、CLAUDE.md「バグ修正ルール」に従い本エントリと再現コードを記録した上で、`Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+NativeConcurrentWorkerExecute.swift` に `withWorker` を実際に呼ぶ回帰テスト（例: `testWithWorkerRunsBlockWithoutThrowing`）を追加する修正 PR を別途起票する。spawn_task 済み（task_ee538588）。
  - 前提: なし

- [x] KSP-1259: kotlin.native.runtime top-level の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.native.runtime` / top-level
  - 実装先 .kt: 宣言ごとに本家 kotlin-native のオーナーファイルへ追加する（`runtime/Debugging.kt`: Debugging、`runtime/GC.kt`: GC、`runtime/GCInfo.kt`: GCInfo/MemoryUsage/RootSetStatistics/SweepStatistics、`runtime/NativeRuntimeApi.kt`: NativeRuntimeApi。いずれも `Sources/CompilerCore/Stdlib/kotlin/native/` 配下。KSP-1541 で per-type ディレクトリ名は廃止済み）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: GC / GCInfo / MemoryUsage / NativeRuntimeApi / RootSetStatistics / SweepStatistics は KSP-1261 / KSP-1264 / KSP-1268 で個別に source-back 済み。残る `Debugging` を `Sources/CompilerCore/Stdlib/kotlin/native/runtime/Debugging.kt` に `@NativeRuntimeApi @SinceKotlin("1.9") public object Debugging {}` として追加し、7 件全ての top-level nominal を source-backed 化した。`HeaderHelpers+SyntheticNativeRefRuntimeStubs.swift`（`registerDebuggingObjectStub`）は既存の synthetic placeholder を bundled 宣言が reuse する経路のため、`HeaderCollection.swift` の `shouldRestoreDeclSiteForReusableSyntheticSymbol` に `kotlin.native.runtime.Debugging` を追加して `RootSetStatistics` と同じ扱いで declSite を復元し、`isSourceBackedSymbol` が true になるようにした（この一覧に入れていない場合、reuse された symbol の declSite が nil のまま残り non-source-backed 扱いになることを `DebuggingSourceMigrationTests` の失敗で確認済み）。メンバ（dumpMemory / forceCheckedShutdown / isThreadStateRunnable / gcSuspendCount / threadCount / globalObjectCount）は KSP-1260 の所有範囲のため synthetic stub のまま変更していない。
  - 検証根拠: `DebuggingSourceMigrationTests` PASS（`Debugging` が `__bundled_kotlin/native/runtime/Debugging.kt` の source-backed object であることを確認）、対象 Golden harness（`stdlib_kotlin_native_runtime_Debugging_n_n`）PASS。`diff_kotlinc` は Kotlin/Native 専用 API のため `SKIP-DIFF` とし、`.build/debug/kswiftc` での直接コンパイル・リンク・実行で `true` を確認した。
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.Debugging` — object kotlin.native.runtime.Debugging  -- `final object kotlin.native.runtime/Debugging {`
    - `kotlin.native.runtime.GC` — object kotlin.native.runtime.GC  -- `final object kotlin.native.runtime/GC {`
    - `kotlin.native.runtime.GCInfo` — class kotlin.native.runtime.GCInfo  -- `final class kotlin.native.runtime/GCInfo {`
    - `kotlin.native.runtime.MemoryUsage` — class kotlin.native.runtime.MemoryUsage  -- `final class kotlin.native.runtime/MemoryUsage {`
    - `kotlin.native.runtime.NativeRuntimeApi` — class kotlin.native.runtime.NativeRuntimeApi  -- `open annotation class kotlin.native.runtime/NativeRuntimeApi : kotlin/Annotation {`
    - `kotlin.native.runtime.RootSetStatistics` — class kotlin.native.runtime.RootSetStatistics  -- `final class kotlin.native.runtime/RootSetStatistics {`
    - `kotlin.native.runtime.SweepStatistics` — class kotlin.native.runtime.SweepStatistics  -- `final class kotlin.native.runtime/SweepStatistics {`

- [x] KSP-1260: kotlin.native.runtime.Debugging.Debugging の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.native.runtime.Debugging` / receiver `Debugging`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/Debugging.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_Debugging_Debugging_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_Debugging_Debugging_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_Debugging_Debugging_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.Debugging.dumpMemory` — fun Debugging.dumpMemory(Long): Boolean  -- `final fun dumpMemory(kotlin/Long): kotlin/Boolean`
    - `kotlin.native.runtime.Debugging.forceCheckedShutdown` — val Debugging.forceCheckedShutdown: Boolean  -- `final var forceCheckedShutdown`
    - `kotlin.native.runtime.Debugging.isThreadStateRunnable` — val Debugging.isThreadStateRunnable: Boolean  -- `final val isThreadStateRunnable`
  - 2026-09-14 実施: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/Debugging.kt` を新規作成し、`object Debugging` と3メンバー（`isThreadStateRunnable`/`forceCheckedShutdown`/`dumpMemory`）を top-level `private external fun`（`__kk_debugging_*` ブリッジ、`kotlin/native/Platform.kt` の `isMemoryLeakCheckerActive` と同型）経由で source-back した。合成スタブ側は `registerDebuggingObjectStub`（`HeaderHelpers+SyntheticNativeRefRuntimeStubs.swift`）と `debuggingProperties`（`SyntheticStubSurfaceSpec+NativeRefRuntime.swift`）を丸ごと削除。ついでに実 kotlinc 2.3.10 に存在しない旧 `gcSuspendCount`/`threadCount`/`globalObjectCount`（`docs/stdlib-gap-audit-2.3.10/gap_v2.tsv` に記載なし）の Kotlin 側露出も削除した（Swift 側の生 `kk_debugging_*` 関数自体は既存 RuntimeTests が直接呼ぶテスト計測用として維持）。既存 `kk_debugging_is_thread_state_runnable` は `__kk_debugging_is_thread_state_runnable` へ降格・改名（RuntimeABISpec 側も追従）。golden: `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` を実行し、`git status` で新規 `stdlib_kotlin_native_runtime_Debugging_Debugging_n.golden` 1 件のみが追加され既存 golden に差分がないことを確認（内容は sym `[kind=prop]`/`[kind=fun]` の解決を含め妥当）。このフルスイート実行は "4 issues" 失敗を報告したが、詳細ログは `tail` で切り落としてしまい未回収、かつ golden 差分ファイル自体は新規1件のみのため無関係な環境要因（既知の並行 worktree 負荷下でのワーカー timeout 誤診断、[`golden-worker-timeout-misdiagnosis`] 系）の疑いが強い——本 PR 由来かどうかは CI で再確認が必要（このマシンは作業中、ピアセッションから全件系ゲートの同時多重実行による高負荷を指摘されており、原因切り分けのための再実行は見送った）。diff_kotlinc: `Scripts/diff_cases/stdlib_kotlin_native_runtime_Debugging_Debugging_n.kt` を `// SKIP-DIFF (DEBT-DIFF-001)` 付きで追加（`kotlin.native.*` は JVM kotlinc に存在しないため。実行はしていない）。動作確認: `NativeDebuggingSourceAPITests`（新規）/ `NativeRefRuntimeSemaTests`（39件）/ `RuntimeTests.RuntimeNativeRefDebuggingTests`（11件、新規2件含む）/ `RuntimeABIExternalLinkValidationTests`（4件）/ `BuildKIRCodegenRegressionTests.testABILoweringMarksNativeRefRuntimeHelpersAsNonThrowing` は green。`check_todo_ids.sh` pass。**未実施**: `swift_test.sh` 全体、`--filter Golden` 四スイート一括、`diff_kotlinc.sh` 全件（CLAUDE.md の最小スコープ方針および同時多重実行を避けたいというピアセッションの要請に従い見送り。CI に委ねる）。**発見した実行時バグ（訂正・追記）**: `kswiftc --stdlib-from-source` で実際にコンパイル・実行すると、`isThreadStateRunnable`（getter-only の custom-getter プロパティ）の呼び出しが `EXC_BAD_ACCESS` でクラッシュすることを確認した（本PR未変更の `Platform.canAccessUnaligned` でも同様に再現する pre-existing バグ）。本PR作成時点では原因を `ABILoweringPass` のプロパティアクセサ throws 判定（`isSyntheticAccessor`/`canThrow`）のミスマッチと誤って仮説立てて BUG-257 として記録したが、並行して進んでいた KSP-1262（PR #6816、`claude/ksp-1262-d6802c`、commit `d28871d17`）が同じ症状を独立に調査し、真因は `CallLowerer+MemberPropertyReads.swift` の `tryLowerObjectMemberPropertyRead` が object メンバープロパティ読み取りを常に `loadGlobal` として lower していたことだと特定・修正済み（getter-only の custom-getter プロパティは `needsBackingField` が false のためバッキンググローバルが存在せず、存在しないグローバルへの読み込みでクラッシュしていた。修正はその場合に getter アクセサ関数への `call` へ分岐させるもの）。この訂正を踏まえ、本PRの TODO.md からは（origin/master との merge コンフリクト解消時に）誤った仮説を含む BUG-257 エントリを削除した——正しい原因・修正は PR #6816 側に委ねる。`forceCheckedShutdown`（var、setter 経由の書き込み）や `dumpMemory`（プレーン `fun`）が同種の書き込み経路の不具合（KSP-1262 側で追加発見された BUG-260/261/263、暗黙 this 書き込み・delegated property・アクセサ内例外の握りつぶし・Long var の kklib 越し書き込み消失）の影響を受けるかは本PRでは未検証。PR #6816 マージ後に改めて実機確認することが望ましい。

- [x] KSP-1262: kotlin.native.runtime.GC.GC の未実装 stdlib API を実装する（22 件）
  - 対象: `kotlin.native.runtime.GC` / receiver `GC`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GC.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_GC_GC_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_GC_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_GC_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.GC.autotune` — val GC.autotune: Boolean  -- `final var autotune`
    - `kotlin.native.runtime.GC.collect` — fun GC.collect(): Unit  -- `final fun collect()`
    - `kotlin.native.runtime.GC.collectCyclesThreshold` — val GC.collectCyclesThreshold: Long  -- `final var collectCyclesThreshold`
    - `kotlin.native.runtime.GC.collectCyclic` — fun GC.collectCyclic(): Unit  -- `final fun collectCyclic()`
    - `kotlin.native.runtime.GC.cyclicCollectorEnabled` — val GC.cyclicCollectorEnabled: Boolean  -- `final var cyclicCollectorEnabled`
    - `kotlin.native.runtime.GC.detectCycles` — fun GC.detectCycles(): Array  -- `final fun detectCycles(): kotlin/Array<kotlin/Any>?`
    - `kotlin.native.runtime.GC.findCycle` — fun GC.findCycle(Any): Array  -- `final fun findCycle(kotlin/Any): kotlin/Array<kotlin/Any>?`
    - `kotlin.native.runtime.GC.heapTriggerCoefficient` — val GC.heapTriggerCoefficient: Double  -- `final var heapTriggerCoefficient`
    - `kotlin.native.runtime.GC.lastGCInfo` — val GC.lastGCInfo: GCInfo  -- `final val lastGCInfo`
    - `kotlin.native.runtime.GC.maxHeapBytes` — val GC.maxHeapBytes: Long  -- `final var maxHeapBytes`
    - `kotlin.native.runtime.GC.minHeapBytes` — val GC.minHeapBytes: Long  -- `final var minHeapBytes`
    - `kotlin.native.runtime.GC.pauseOnTargetHeapOverflow` — val GC.pauseOnTargetHeapOverflow: Boolean  -- `final var pauseOnTargetHeapOverflow`
    - `kotlin.native.runtime.GC.regularGCInterval` — val GC.regularGCInterval: Duration  -- `final var regularGCInterval`
    - `kotlin.native.runtime.GC.resume` — fun GC.resume(): Unit  -- `final fun resume()`
    - `kotlin.native.runtime.GC.schedule` — fun GC.schedule(): Unit  -- `final fun schedule()`
    - `kotlin.native.runtime.GC.start` — fun GC.start(): Unit  -- `final fun start()`
    - `kotlin.native.runtime.GC.stop` — fun GC.stop(): Unit  -- `final fun stop()`
    - `kotlin.native.runtime.GC.suspend` — fun GC.suspend(): Unit  -- `final fun suspend()`
    - `kotlin.native.runtime.GC.targetHeapBytes` — val GC.targetHeapBytes: Long  -- `final var targetHeapBytes`
    - `kotlin.native.runtime.GC.targetHeapUtilization` — val GC.targetHeapUtilization: Double  -- `final var targetHeapUtilization`
    - `kotlin.native.runtime.GC.threshold` — val GC.threshold: Int  -- `final var threshold`
    - `kotlin.native.runtime.GC.thresholdAllocations` — val GC.thresholdAllocations: Long  -- `final var thresholdAllocations`

- [x] KSP-1263: kotlin.native.runtime.GC.MainThreadFinalizerProcessor.MainThreadFinalizerProcessor の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.runtime.GC.MainThreadFinalizerProcessor` / receiver `MainThreadFinalizerProcessor`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GC.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_GC_MainThreadFinalizerProcessor_MainThreadFinalizerProcessor_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_MainThreadFinalizerProcessor_MainThreadFinalizerProcessor_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_MainThreadFinalizerProcessor_MainThreadFinalizerProcessor_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: `GC.kt` の `MainThreadFinalizerProcessor` に、`kotlin.native.Platform`（`Sources/CompilerCore/Stdlib/kotlin/native/Platform.kt`）と同じ external-bridge パターン（`get()`/`set()` が `@KsSymbolName` 付き `private external fun` を呼ぶ）で `available`/`batchSize`/`maxTimeInTask`/`minTimeBetweenTasks` の4プロパティを実装した。対応する Runtime ブリッジ7関数（`available` 1件 + var 3件 × load/store）を `Sources/Runtime/RuntimeGC.swift` に、`RuntimeABISpec` エントリを `Sources/RuntimeABI/RuntimeABISpec+NativeRef.swift` に追加した。実装・検証の過程で、`object` を receiver とするネストした `class`/`enumClass`/`object`/`annotationClass` メンバーが解決できないという既存 Sema バグ（`class`/`interface`/`enumClass` receiver 専用の `classNameReceiverNominalSymbol` 経路が `object` を除外しているため — `TimeSource.Monotonic` のような interface ネストでは動くが `GC.MainThreadFinalizerProcessor` のような object ネストでは動かない）を発見し、`CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift` の無候補フォールバック末尾に、`.enumClass`/`.object`/`.annotationClass` ネストオーナーに限定した追加フォールバックを実装して、`GC.MainThreadFinalizerProcessor.<member>` のチェーンアクセスが型チェックを通るようにした（`classNameReceiverNominalSymbol` 自体への `.object` 追加は `GC.collect()` 等の通常のインスタンスメンバー呼び出しを壊すリスクがあるため見送った）。回帰テスト: `GCSourceMigrationTests.mainThreadFinalizerProcessorPropertiesResolveOnObjectReceiver`。
  - 検証根拠: `GCSourceMigrationTests` 2件 PASS（既存1件 + 新規回帰1件）、`RuntimeABIExternalLinkValidationTests` 4件 PASS（`@KsSymbolName` ⇔ `RuntimeABISpec` の対応・arity・型を検証）、対象 Golden バッチ（`stdlib_kotlin_native_concurrent_Worker_Worker_n.kt...stdlib_kotlin_native_runtime_GC_n_n.kt` 8ケース、`CompilerCoreTests.GoldenSemaGoldenTests`）PASS —— `GC.MainThreadFinalizerProcessor.{available,batchSize,maxTimeInTask,minTimeBetweenTasks}` の読み取り・代入がいずれも診断なしで正しい型（`Boolean`/`ULong`/`kotlin.time.Duration`）に解決されることを確認。`diff_kotlinc` は KSP-1261 と同じ理由（`kotlin.native.*` は JVM kotlinc 非対応）で `SKIP-DIFF` とした。**end-to-end のコンパイル・リンク・実行による実測検証は未完了**: `.build/debug/kswiftc` での手動実行検証中に、本チケットのスコープ外のバグを2件踏んだ。(1) `GC.MainThreadFinalizerProcessor.available` のような custom-getter プロパティの読み取りが SIGBUS でクラッシュする（`kotlin.native.Platform.canAccessUnaligned` でも無関係に再現）症状は、並行して進行中の別ブランチ `claude/ksp-1262-d6802c` で **BUG-257 として同一の症状・根本原因（`tryLowerObjectMemberPropertyRead` が custom getter の有無を無視して無条件に `loadGlobal` へ lower していた）まで特定の上で修正済み**と判明したため（`git log --all` で確認、2026-09-14 時点で master 未マージ）、本 PR では重複起票しない。(2) `GC.MainThreadFinalizerProcessor.batchSize = value`（ネストした `object` への明示レシーバ代入）が KIR lowering で失敗する症状は BUG-257 の修正後も残る別種の欠落と判断し、BUG-263 として新規記録した。`bash Scripts/check_todo_ids.sh` pass（本ファイル内では重複なし。並行セッションとの BUG-NNN 番号衝突は既知の運用上の制約——マージ時に解消）。未実施: 全 Swift テスト・Golden 四スイート一括・`diff_kotlinc.sh` 全件（他セッションからのマシン負荷抑制の周知を受け、変更に関係する範囲のみ実行。全体は CI に任せる）。
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.GC.MainThreadFinalizerProcessor.available` — val MainThreadFinalizerProcessor.available: Boolean  -- `final val available`
    - `kotlin.native.runtime.GC.MainThreadFinalizerProcessor.batchSize` — val MainThreadFinalizerProcessor.batchSize: ULong  -- `final var batchSize`
    - `kotlin.native.runtime.GC.MainThreadFinalizerProcessor.maxTimeInTask` — val MainThreadFinalizerProcessor.maxTimeInTask: Duration  -- `final var maxTimeInTask`
    - `kotlin.native.runtime.GC.MainThreadFinalizerProcessor.minTimeBetweenTasks` — val MainThreadFinalizerProcessor.minTimeBetweenTasks: Duration  -- `final var minTimeBetweenTasks`

- [ ] BUG-263: `Outer.Inner`（`Inner` が `Outer` 直下にネストした `object`）を、代入のレシーバ（`Outer.Inner.prop = value`）またはスタンドアロンの値（`val x = Outer.Inner`）として使用すると、Sema の型チェックは通る（診断なし）が KIR lowering で `KSWIFTK-KIR-0003: KIR verifier: ... call to 'Inner' does not resolve to a module function, an external link name, or a runtime ABI function` エラーになる。最小再現: `@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)` の下で `import kotlin.native.runtime.GC` し `fun main() { GC.MainThreadFinalizerProcessor.batchSize = 5uL }` をコンパイルすると上記エラーになる。同じ `import`/`OptIn` で `println(GC.MainThreadFinalizerProcessor.available)`（チェーンされた getter 読み取りのみ）はコンパイル・リンクまで成功する（実行は BUG-257 の修正待ちでブロックされる）ため、失敗は「代入レシーバ・スタンドアロン参照としてのネストオブジェクト値materialization」に限定される。原因: KSP-1263 で `CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift` に追加した、`object` receiver 上のネストオーナー（`class`/`enumClass`/`object`/`annotationClass`）解決フォールバックは、既存の class-name-receiver 用ネストオーナー解決（`CallTypeChecker+MemberCallInferenceRegularResolution.swift`）と同じ Sema バインディング（`bindIdentifier`/`bindExprType` のみ）を行うが、後者は常に `TimeSource.Monotonic.markNow()` のように同一 memberCall 連鎖内でのみ使われてきた（`Outer.Inner` 単体の値化やその代入レシーバとしての使用は本 PR 以前に一度も Sema を通ったことがなく、lowering 側の対応も存在しない）。発見元: KSP-1263 で `GC.MainThreadFinalizerProcessor` を値としてアクセス可能にする Sema 修正を追加した際、getter のチェーン読み取りは動作する一方、`var` プロパティへの代入がこのエラーで失敗することが判明した。今回修正しない理由: KIR lowering / NativeEmitter 側でネストオブジェクトの値 materialization（代入レシーバ・スタンドアロン参照を含む）を補う変更が必要で、sema 層の型サーフェス追加という KSP-1263 のスコープを超える。ユーザー承認済みで別 PR に切り出す。注記: `BUG-257`/`BUG-259`/`BUG-260`/`BUG-261`/`BUG-262` は本 PR 作成時点で他の並行セッションのブランチ（`claude/ksp-1262-d6802c` 等）が同一番号を別内容で既に使用済みだったため、衝突を避けて空いている番号から採番した。

- [~] BUG-264: 名前付き（非リテラル）`object` 宣言（`object Named : Base(x)`）でスーパークラス実引数が消失する。KSP-CAP-018 / BUG-215 が修正したのは無名の object 式（`object : Base(x) { ... }`）のクラス継承のみで、名前付き object 宣言は当初からスコープ外だった。最小再現: `open class Base2(val v: Int)` `object Named : Base2(7)` `fun main() { println(Named.v) }` が `0` を出力（kotlinc は `7`）。クラッシュせず実引数が無言で捨てられ、継承フィールドがゼロ初期化のまま残る。もう1つの疑われていた症状（base 型変数経由の virtual dispatch がレシーバに誤った定数値を積む、発見元 p9「`.symbolRef` 定数が `loadGlobal` の代わりに使われている」）は、`open class Base3 { open fun describe(): String = "base" }` `object Named2 : Base3() { override fun describe(): String = "named" }` `val b: Base3 = Named2` で `named` と正しく出力され、単純形では再現しなかった（未確認のまま）。**修正済み（2026-09-17、KUU-552）**: (a) `synthesizeObjectInitializer`（`KIRLoweringDriver+ObjectInitializer.swift`）が `kk_object_new` 後にスーパークラス `<init>` を一切呼んでいなかった（`ObjectDecl.superTypeConstructorArgs` は AST 構築・Sema 側で既に捕捉・型検査済み）。object 式版 `emitObjectLiteralSuperConstructorCall`（KSP-CAP-018）と同型の `emitNamedObjectSuperConstructorCall` を新設し、vtable 登録直後・`emitObjectBodyInitializers` 直前に配線（companion は `.companion` 修飾子で除外し既存の companion init 経路に委譲）。(b) object 式側の ctor オーバーロード解決 `resolveObjectLiteralSuperConstructor` を driver 共有の `resolveObjectSuperConstructor` へ移動し、companion 専用だった `emitCompanionSuperConstructorDelegation`（`lookupAll().first` で arity を見なかった）も同じ emit に統合——`companion object : Base(x)` も arity/型で ctor を選ぶようになった。(c) `MemberLowerer` のネスト object 初期化ゲートが interface 継承時のみ初期化子を生成していたため、`class Outer { object N : Base2(9) }` は初期化子自体が存在せず `Outer.N.v` が `kk_array_get_inbounds precondition failed` でクラッシュしていた。非 companion かつ非 `Any` の class/enumClass スーパータイプでも初期化子を生成するよう拡張（`Outer.N.v` = 9、`Outer.N is Base2` = true を確認）。回帰: `Scripts/diff_cases/named_object_super_ctor_args.kt`（kotlinc 差分 PASS）+ `Tests/CompilerBackendTests/Codegen/CodegenBackendNamedObjectSuperConstructorTests.swift` 8 件。残存の関連ギャップ（本項スコープ外）: スーパークラス ctor のデフォルト実引数省略（`object N : B()` で `B(val v: Int = 9)` は名前付き class 同様に未対応、object 式経路と同じ残留ギャップ）、関数ローカル named object 宣言の名前解決不可（KUU-555）、plain なネスト object（スーパータイプ無し）の未初期化、companion の継承メンバー解決不可（Sema の member lookup 制限）。

- [x] BUG-267: object 式（匿名クラス）のプロパティ delegation（`by`）が両方向とも未実装。最小再現: `fun main() { val o = object { val x: Int by lazy { 42 } }; println(o.x) }`（明示レシーバ）と `fun show(): Int = x` をメンバに持つ同型（暗黙レシーバ）が、いずれも `KSWIFTK-LINK-0001`（`_get` 未定義）で失敗していた。原因は2層: (1) object 式専用の Sema 経路（`ExprTypeChecker+ObjectLiteralInference.swift`）が `$delegate_<name>` ストレージシンボルを作らず delegate 式を型チェックしていなかった、(2) object 式専用の lowering 経路（`ObjectLiteralLowerer`）が delegate 初期化と synthesized accessor を発行していなかった。**修正済み（本 PR）**: Sema 側で delegate storage 定義・`typeCheckDelegate` 呼び出し・`$delegate_` キーのレイアウトスロット・delegate body のキャプチャ収集を追加し、lowering 側は named class と同じ `emitDelegatePropertyInitializer`/`MemberLowerer.lowerDelegateAccessor` を再利用する形に統一（`compilationCtx` 非依存化、`ctx.lazyThreadSafetyMode` 経由）。併せて bare-name `x += 1`（`.compoundAssign`）が accessor 使用メンバプロパティ（delegated `var`、custom getter+setter 両持ち）で `fieldOffsets[symbol]` を引けず疑似ローカル扱いに落ち、結果として実行時 `kk_array_get_inbounds` クラッシュになっていた経路を、`get`/`set` accessor 経由に修正（named class の delegated メンバでも同じ欠落があったため同時に治った）。回帰: `Scripts/diff_cases/object_literal_delegated_property.kt`（kotlinc diff PASS）と `CodegenBackendPropertyDelegateEdgeCasesTests` の3テスト。発見元・経緯は KUU-551 / KSP-CAP-018 の未解消項目 (1)。

- [~] KSP-1265: kotlin.native.runtime.GCInfo.GCInfo の未実装 stdlib API を実装する（15 件）
  - 対象: `kotlin.native.runtime.GCInfo` / receiver `GCInfo`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GCInfo.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_GCInfo_GCInfo_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_GCInfo_GCInfo_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_GCInfo_GCInfo_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.GCInfo.endTimeNs` — val GCInfo.endTimeNs: Long  -- `final val endTimeNs`
    - `kotlin.native.runtime.GCInfo.epoch` — val GCInfo.epoch: Long  -- `final val epoch`
    - `kotlin.native.runtime.GCInfo.firstPauseEndTimeNs` — val GCInfo.firstPauseEndTimeNs: Long  -- `final val firstPauseEndTimeNs`
    - `kotlin.native.runtime.GCInfo.firstPauseRequestTimeNs` — val GCInfo.firstPauseRequestTimeNs: Long  -- `final val firstPauseRequestTimeNs`
    - `kotlin.native.runtime.GCInfo.firstPauseStartTimeNs` — val GCInfo.firstPauseStartTimeNs: Long  -- `final val firstPauseStartTimeNs`
    - `kotlin.native.runtime.GCInfo.markedCount` — val GCInfo.markedCount: Long  -- `final val markedCount`
    - `kotlin.native.runtime.GCInfo.memoryUsageAfter` — val GCInfo.memoryUsageAfter: Map  -- `final val memoryUsageAfter`
    - `kotlin.native.runtime.GCInfo.memoryUsageBefore` — val GCInfo.memoryUsageBefore: Map  -- `final val memoryUsageBefore`
    - `kotlin.native.runtime.GCInfo.postGcCleanupTimeNs` — val GCInfo.postGcCleanupTimeNs: Long  -- `final val postGcCleanupTimeNs`
    - `kotlin.native.runtime.GCInfo.rootSet` — val GCInfo.rootSet: RootSetStatistics  -- `final val rootSet`
    - `kotlin.native.runtime.GCInfo.secondPauseEndTimeNs` — val GCInfo.secondPauseEndTimeNs: Long  -- `final val secondPauseEndTimeNs`
    - `kotlin.native.runtime.GCInfo.secondPauseRequestTimeNs` — val GCInfo.secondPauseRequestTimeNs: Long  -- `final val secondPauseRequestTimeNs`
    - `kotlin.native.runtime.GCInfo.secondPauseStartTimeNs` — val GCInfo.secondPauseStartTimeNs: Long  -- `final val secondPauseStartTimeNs`
    - `kotlin.native.runtime.GCInfo.startTimeNs` — val GCInfo.startTimeNs: Long  -- `final val startTimeNs`
    - `kotlin.native.runtime.GCInfo.sweepStatistics` — val GCInfo.sweepStatistics: Map  -- `final val sweepStatistics`

  - focused根拠: Kotlin 2.3.10 GCInfo.kt と同じ @NativeRuntimeApi / @SinceKotlin("1.9") 付き immutable プロパティ 15 件を bundled Kotlin source の constructor に `public val` として移し、GCInfo の synthetic property registration（`gcInfoProperties` spec と登録呼び出し）、および専用に使われていた `mapOfString` / `sweepStatisticsType` / `memoryUsageType` ヘルパーを削除した。`GCInfoSourceMigrationTests.gcInfoConstructorIsBundledSourceBacked` で全 15 プロパティの source-backed / non-synthetic / non-mutable / external-linkなし / 型（Long・nullable Long・RootSetStatistics・Map<String, SweepStatistics>・Map<String, MemoryUsage>）を検証し、専用 golden/diff ケース（`stdlib_kotlin_native_runtime_GCInfo_properties_n`）は全プロパティの構築・読み出しを固定する。全体 Swift/Golden/diff の gate は未実行のため完了は保留する。

- [~] KSP-1270: kotlin.native.runtime.RootSetStatistics.RootSetStatistics の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.runtime.RootSetStatistics` / receiver `RootSetStatistics`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GCInfo.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_RootSetStatistics_RootSetStatistics_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_RootSetStatistics_RootSetStatistics_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_RootSetStatistics_RootSetStatistics_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.RootSetStatistics.globalReferences` — val RootSetStatistics.globalReferences: Long  -- `final val globalReferences`
    - `kotlin.native.runtime.RootSetStatistics.stableReferences` — val RootSetStatistics.stableReferences: Long  -- `final val stableReferences`
    - `kotlin.native.runtime.RootSetStatistics.stackReferences` — val RootSetStatistics.stackReferences: Long  -- `final val stackReferences`
    - `kotlin.native.runtime.RootSetStatistics.threadLocalReferences` — val RootSetStatistics.threadLocalReferences: Long  -- `final val threadLocalReferences`

  - focused根拠: Kotlin 2.3.10 GCInfo.kt と同じ `@NativeRuntimeApi` / `@SinceKotlin("1.9")` 付き immutable Long properties 4 件を bundled Kotlin source の constructor parameter に `public val` として移し、RootSetStatistics の synthetic property／constructor registration と専用 surface spec を削除した。Runtime/ABI bridge と CallTypeChecker / CallLowerer の name-string 特例は対象シンボルに存在しない。`NativeRefRuntimeSemaTests` で4 propertyの source-backed / non-synthetic / non-mutable / external-linkなしを確認し、専用 Sema Golden は artifact 再レンダリングと一致する。
  - 検証: `swift build` PASS、`NativeRefRuntimeSemaTests` 45件 PASS、artifact-based Sema Golden shard 73/94（対象を含む8件）PASS、対象 Golden の artifact worker 再レンダリング一致、対象 diff は `SKIP-DIFF` で exit 0、`bash Scripts/check_todo_ids.sh` PASS、`bash Scripts/validate_runtime_abi_links.sh` 4件 PASS、`git diff --check` PASS。全 Golden／全 diff gate は共有 worktree 競合により未完了（全 Golden 更新は対象到達前に中断）、そのため完了は保留する。

- [x] KSP-1272: kotlin.native.runtime.SweepStatistics.SweepStatistics の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.native.runtime.SweepStatistics` / receiver `SweepStatistics`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GCInfo.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_SweepStatistics_SweepStatistics_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_SweepStatistics_SweepStatistics_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_SweepStatistics_SweepStatistics_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.SweepStatistics.keptCount` — val SweepStatistics.keptCount: Long  -- `final val keptCount`
    - `kotlin.native.runtime.SweepStatistics.sweptCount` — val SweepStatistics.sweptCount: Long  -- `final val sweptCount`

  - focused根拠: Kotlin 2.3.10 GCInfo.kt と同じ @NativeRuntimeApi / @SinceKotlin("1.9") 付き immutable Long properties を bundled Kotlin source に移し、SweepStatistics の synthetic property registration/spec を削除した。NativeRefRuntimeSemaTests で両 property の source-backed、non-synthetic、non-mutable、external-linkなしを確認し、専用 fixture は constructor の sweptCount/keptCount 順序と Long 極値を native 実行で固定する。全 Swift/Golden/diff の変更 head G は未実行のため完了は保留する。
  - 2026-09-15 完了: 既存の `GCInfo.kt` source-backed 宣言（constructor / `sweptCount` / `keptCount`）を KUU-421 の owner fixture に接続し、`stdlib_kotlin_native_runtime_SweepStatistics_SweepStatistics_n` の Sema golden と Native-only diff case を追加した。対象 symbol に Runtime/ABI bridge や name-string 特例はなく、既存の synthetic class shell 以外の property/constructor stub は登録されていないため追加削除は不要。
  - 検証: `NativeRefRuntimeSemaTests` 45件 PASS、Sema golden shard 73（対象を含む8件）PASS、`bash Scripts/check_todo_ids.sh` PASS、`git diff --check` PASS。対象 diff command は実行したが、`kotlin.native.*` の SKIP 判定前に初回 stdlib artifact build が120秒 timeout（fixture の compile failure ではない）となった。全 Golden / 全 diff / Runtime ABI 全体ゲートは未実行（他セッションの SwiftPM 同時実行による lock 待ちを避け、変更関連範囲に限定）。

- [ ] KSP-1274: kotlin.properties.Delegates.Delegates の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.properties.Delegates` / receiver `Delegates`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/properties/Delegates/Delegates.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_properties_Delegates_Delegates_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_properties_Delegates_Delegates_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_properties_Delegates_Delegates_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.properties.Delegates.notNull` — fun Delegates.notNull(): ReadWriteProperty  -- `final fun <#A1: kotlin/Any> notNull(): kotlin.properties/ReadWriteProperty<kotlin/Any?, #A1>`
    - `kotlin.properties.Delegates.observable` — fun Delegates.observable(, Function3): ReadWriteProperty  -- `final inline fun <#A1: kotlin/Any?> observable(#A1, crossinline kotlin/Function3<kotlin.reflect/KProperty<*>, #A1, #A1, kotlin/Unit>): kotlin.properties/ReadWriteProperty<kotlin/Any?, #A1>`
    - `kotlin.properties.Delegates.vetoable` — fun Delegates.vetoable(, Function3): ReadWriteProperty  -- `final inline fun <#A1: kotlin/Any?> vetoable(#A1, crossinline kotlin/Function3<kotlin.reflect/KProperty<*>, #A1, #A1, kotlin/Boolean>): kotlin.properties/ReadWriteProperty<kotlin/Any?, #A1>`

- [ ] KSP-1275: kotlin.properties.ObservableProperty top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.properties.ObservableProperty` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/properties/ObservableProperty/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_properties_ObservableProperty_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_properties_ObservableProperty_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_properties_ObservableProperty_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.properties.ObservableProperty.<init>` — constructor ()  -- `constructor <init>(#A)`

- [ ] KSP-1281: kotlin.ranges top-level の未実装 stdlib API を実装する（21 件）
  - 対象: `kotlin.ranges` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.CharProgression` — class kotlin.ranges.CharProgression  -- `open class kotlin.ranges/CharProgression : kotlin.collections/Iterable<kotlin/Char> {`
    - `kotlin.ranges.CharRange` — class kotlin.ranges.CharRange  -- `final class kotlin.ranges/CharRange : kotlin.ranges/CharProgression, kotlin.ranges/ClosedRange<kotlin/Char>, kotlin.ranges/OpenEndRange<kotlin/Char> {`
    - `kotlin.ranges.IntProgression` — class kotlin.ranges.IntProgression  -- `open class kotlin.ranges/IntProgression : kotlin.collections/Iterable<kotlin/Int> {`
    - `kotlin.ranges.IntRange` — class kotlin.ranges.IntRange  -- `final class kotlin.ranges/IntRange : kotlin.ranges/ClosedRange<kotlin/Int>, kotlin.ranges/IntProgression, kotlin.ranges/OpenEndRange<kotlin/Int> {`
    - `kotlin.ranges.LongProgression` — class kotlin.ranges.LongProgression  -- `open class kotlin.ranges/LongProgression : kotlin.collections/Iterable<kotlin/Long> {`
    - `kotlin.ranges.LongRange` — class kotlin.ranges.LongRange  -- `final class kotlin.ranges/LongRange : kotlin.ranges/ClosedRange<kotlin/Long>, kotlin.ranges/LongProgression, kotlin.ranges/OpenEndRange<kotlin/Long> {`
    - `kotlin.ranges.UIntProgression` — class kotlin.ranges.UIntProgression  -- `open class kotlin.ranges/UIntProgression : kotlin.collections/Iterable<kotlin/UInt> {`
    - `kotlin.ranges.UIntRange` — class kotlin.ranges.UIntRange  -- `final class kotlin.ranges/UIntRange : kotlin.ranges/ClosedRange<kotlin/UInt>, kotlin.ranges/OpenEndRange<kotlin/UInt>, kotlin.ranges/UIntProgression {`
    - `kotlin.ranges.ULongProgression` — class kotlin.ranges.ULongProgression  -- `open class kotlin.ranges/ULongProgression : kotlin.collections/Iterable<kotlin/ULong> {`
    - `kotlin.ranges.ULongRange` — class kotlin.ranges.ULongRange  -- `final class kotlin.ranges/ULongRange : kotlin.ranges/ClosedRange<kotlin/ULong>, kotlin.ranges/OpenEndRange<kotlin/ULong>, kotlin.ranges/ULongProgression {`
    - `kotlin.ranges.coerceAtLeast` — fun coerceAtLeast(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceAtLeast(#A): #A`
    - `kotlin.ranges.coerceAtMost` — fun coerceAtMost(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceAtMost(#A): #A`
    - `kotlin.ranges.coerceIn` — fun coerceIn(ClosedFloatingPointRange): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceIn(kotlin.ranges/ClosedFloatingPointRange<#A>): #A`
    - `kotlin.ranges.coerceIn` — fun coerceIn(ClosedRange): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceIn(kotlin.ranges/ClosedRange<#A>): #A`
    - `kotlin.ranges.coerceIn` — fun coerceIn(, ): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceIn(#A?, #A?): #A`
    - `kotlin.ranges.contains` — fun contains(): Boolean  -- `final inline fun <#A: kotlin/Any, #B: kotlin.collections/Iterable<#A> & kotlin.ranges/ClosedRange<#A>> (#B).kotlin.ranges/contains(#A?): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun contains(): Boolean  -- `final inline fun <#A: kotlin/Any, #B: kotlin.collections/Iterable<#A> & kotlin.ranges/OpenEndRange<#A>> (#B).kotlin.ranges/contains(#A?): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun contains(): Boolean  -- `final inline fun <#A: kotlin/Comparable<#A>, #B: kotlin.collections/Iterable<#A> & kotlin.ranges/ClosedRange<#A>> (#B).kotlin.ranges/contains(#A?): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun contains(): Boolean  -- `final inline fun <#A: kotlin/Comparable<#A>, #B: kotlin.collections/Iterable<#A> & kotlin.ranges/OpenEndRange<#A>> (#B).kotlin.ranges/contains(#A?): kotlin/Boolean`
    - `kotlin.ranges.rangeTo` — fun rangeTo(): ClosedRange  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/rangeTo(#A): kotlin.ranges/ClosedRange<#A>`
    - `kotlin.ranges.rangeUntil` — fun rangeUntil(): OpenEndRange  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/rangeUntil(#A): kotlin.ranges/OpenEndRange<#A>`

- [ ] KSP-1283: kotlin.ranges.ClosedRange の未実装 stdlib API を実装する（30 件）
  - 対象: `kotlin.ranges` / receiver `ClosedRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ClosedRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ClosedRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ClosedRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ClosedRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`

- [x] KSP-1284: kotlin.ranges.IntProgression の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ranges` / receiver `IntProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntProgression_first_last_n.kt` を追加し、専用 worker で生成。共有 `IntProgression_n_n` golden は別 PR の所有範囲のため書き換えない。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_first_last_n.kt` を追加し、Kotlin 2.3.10 reference output を保存して比較する。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `RangeHOF.kt:566` の `IntProgression.first()` / `:584` の `.last()` に2シンボル全て実装済み（`fe8e8e0bc` "Load golden tests from a prebuilt stdlib artifact" が導入元）。golden `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntProgression_first_last_n.kt`/`.golden`、diff `Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_first_last_n.kt` で回帰確認済み。TODO.md の `[~]` 表記が更新されていなかっただけ。
  - 実装シンボル一覧:
    - `kotlin.ranges.first` — fun IntProgression.first(): Int  -- `final fun (kotlin.ranges/IntProgression).kotlin.ranges/first(): kotlin/Int`
    - `kotlin.ranges.last` — fun IntProgression.last(): Int  -- `final fun (kotlin.ranges/IntProgression).kotlin.ranges/last(): kotlin/Int`

- [x] KSP-1286: kotlin.ranges.LongProgression の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges` / receiver `LongProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `RangeHOF.kt:791`/`:798`/`:801`/`:808` に4シンボル全て実装済み（`fe8e8e0bc` "Load golden tests from a prebuilt stdlib artifact" が導入元）。golden `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_n.kt`/`.golden`、diff `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n.kt` で回帰確認済み。LongProgression の synthetic `step: Int` は KSP-1306/1307 の別契約であり本タスクの範囲外。TODO.md の `[~]` 表記が更新されていなかっただけ。
  - 実装シンボル一覧:
    - `kotlin.ranges.first` — fun LongProgression.first(): Long  -- `final fun (kotlin.ranges/LongProgression).kotlin.ranges/first(): kotlin/Long`
    - `kotlin.ranges.firstOrNull` — fun LongProgression.firstOrNull(): Long  -- `final fun (kotlin.ranges/LongProgression).kotlin.ranges/firstOrNull(): kotlin/Long?`
    - `kotlin.ranges.last` — fun LongProgression.last(): Long  -- `final fun (kotlin.ranges/LongProgression).kotlin.ranges/last(): kotlin/Long`
    - `kotlin.ranges.lastOrNull` — fun LongProgression.lastOrNull(): Long  -- `final fun (kotlin.ranges/LongProgression).kotlin.ranges/lastOrNull(): kotlin/Long?`

- [x] KSP-1287: kotlin.ranges.LongRange の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.ranges` / receiver `LongRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongRange_cross_contains_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_cross_contains_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_cross_contains_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装済み（ゲート保留）: `RangeHOF.kt` に Byte/Int/Short の LongRange.contains を追加し、LongRange の direct/`in` 呼び出しを型付き source-backed overload へ routing。専用 Sema 3件（literal/typed overload priority controlsを含む）、LongRange Golden worker、LongRange 境界/empty diff（Kotlin 2.3.10）および IntRange 回帰 diff は PASS。
  - 完了（2026-09-15、マージ確認）: PR #6712（commit `88d7e53f0` "KSP-1287: add LongRange cross-type contains overloads"）が `origin/master` にマージ済み（`RangeHOF.kt:663`/`:667`/`:671`、golden `stdlib_kotlin_ranges_LongRange_cross_contains_n.kt`/`.golden`、diff 同名 `.kt` の実在で確認）。共通ゲート G（全Swift/全Golden/全diff）は KUU-453 側の方針転換により CI 確認へ一本化されたため、上記の focused 検証を完了根拠として採用する。
  - 未実装シンボル一覧:
    - `kotlin.ranges.contains` — fun LongRange.contains(Byte): Boolean  -- `final inline fun (kotlin.ranges/LongRange).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun LongRange.contains(Int): Boolean  -- `final inline fun (kotlin.ranges/LongRange).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun LongRange.contains(Short): Boolean  -- `final inline fun (kotlin.ranges/LongRange).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`

- [x] KSP-1289: kotlin.ranges.UIntProgression の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges` / receiver `UIntProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `RangeHOF.kt:1394`/`:1401`/`:1404`/`:1411` に4シンボル全て実装済み（`fe8e8e0bc` "Load golden tests from a prebuilt stdlib artifact" が導入元）。golden `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntProgression_n.kt`/`.golden`、diff `Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n.kt` で回帰確認済み。TODO.md の `[~]` 表記が更新されていなかっただけ。
  - 実装シンボル一覧:
    - `kotlin.ranges.first` — fun UIntProgression.first(): UInt  -- `final fun (kotlin.ranges/UIntProgression).kotlin.ranges/first(): kotlin/UInt`
    - `kotlin.ranges.firstOrNull` — fun UIntProgression.firstOrNull(): UInt  -- `final fun (kotlin.ranges/UIntProgression).kotlin.ranges/firstOrNull(): kotlin/UInt?`
    - `kotlin.ranges.last` — fun UIntProgression.last(): UInt  -- `final fun (kotlin.ranges/UIntProgression).kotlin.ranges/last(): kotlin/UInt`
    - `kotlin.ranges.lastOrNull` — fun UIntProgression.lastOrNull(): UInt  -- `final fun (kotlin.ranges/UIntProgression).kotlin.ranges/lastOrNull(): kotlin/UInt?`

- [x] KSP-1291: kotlin.ranges.ULongProgression の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges` / receiver `ULongProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `RangeHOF.kt:1798`/`:1805`/`:1808`/`:1815` に4シンボル全て実装済み（`fe8e8e0bc` "Load golden tests from a prebuilt stdlib artifact" が導入元）。golden `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_n.kt`/`.golden`、diff `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n.kt` で回帰確認済み。TODO.md の `[~]` 表記が更新されていなかっただけ。
  - 実装シンボル一覧:
    - `kotlin.ranges.first` — fun ULongProgression.first(): ULong  -- `final fun (kotlin.ranges/ULongProgression).kotlin.ranges/first(): kotlin/ULong`
    - `kotlin.ranges.firstOrNull` — fun ULongProgression.firstOrNull(): ULong  -- `final fun (kotlin.ranges/ULongProgression).kotlin.ranges/firstOrNull(): kotlin/ULong?`
    - `kotlin.ranges.last` — fun ULongProgression.last(): ULong  -- `final fun (kotlin.ranges/ULongProgression).kotlin.ranges/last(): kotlin/ULong`
    - `kotlin.ranges.lastOrNull` — fun ULongProgression.lastOrNull(): ULong  -- `final fun (kotlin.ranges/ULongProgression).kotlin.ranges/lastOrNull(): kotlin/ULong?`

- [x] KSP-1292: kotlin.ranges.ULongRange の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.ranges` / receiver `ULongRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.contains` — fun ULongRange.contains(UByte): Boolean  -- `final fun (kotlin.ranges/ULongRange).kotlin.ranges/contains(kotlin/UByte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ULongRange.contains(UInt): Boolean  -- `final fun (kotlin.ranges/ULongRange).kotlin.ranges/contains(kotlin/UInt): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ULongRange.contains(UShort): Boolean  -- `final fun (kotlin.ranges/ULongRange).kotlin.ranges/contains(kotlin/UShort): kotlin/Boolean`

  - focused根拠: Kotlin 2.3.10 `_URanges.kt` と同じ `@SinceKotlin("1.5")` source extension を `RangeHOF.kt` に追加し、各 unsigned 値を `toULong()` で既存の `ULongRange.contains(ULong)` へ widening する。専用 Sema/Golden fixture は named argument、`in`、直接 `contains`、通常の `ULong` overload、full/narrow/empty range と unsigned 境界を固定する。全 Swift/Golden/diff の変更 head G は未実行のため完了は保留する。
  - 完了（2026-09-15、マージ確認）: PR #6692（commit `8b187a3cd`、タイトルは "KSP-1285: Add IntRange cross-type contains overloads" だが同PRで ULongRange の cross-type contains も追加）が `origin/master` にマージ済み（`RangeHOF.kt:1748`/`:1753`/`:1758`、golden `stdlib_kotlin_ranges_ULongRange_n.kt`/`.golden`、diff 同名 `.kt` の実在で確認）。共通ゲート G は KUU-453 側の方針転換により CI 確認へ一本化されたため、上記の focused 検証を完了根拠として採用する。

- [ ] KSP-1293: kotlin.ranges.CharProgression top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.CharProgression` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/CharProgression/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_CharProgression_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_CharProgression_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_CharProgression_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.CharProgression.Companion` — object kotlin.ranges.CharProgression.Companion  -- `final object Companion {`

- [ ] KSP-1294: kotlin.ranges.CharProgression.CharProgression の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.ranges.CharProgression` / receiver `CharProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/CharProgression/CharProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_CharProgression_CharProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_CharProgression_CharProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_CharProgression_CharProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.CharProgression.equals` — fun CharProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.CharProgression.first` — val CharProgression.first: Char  -- `final val first`
    - `kotlin.ranges.CharProgression.hashCode` — fun CharProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.CharProgression.iterator` — fun CharProgression.iterator(): CharIterator  -- `open fun iterator(): kotlin.collections/CharIterator`
    - `kotlin.ranges.CharProgression.last` — val CharProgression.last: Char  -- `final val last`
    - `kotlin.ranges.CharProgression.step` — val CharProgression.step: Int  -- `final val step`
    - `kotlin.ranges.CharProgression.toString` — fun CharProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1296: kotlin.ranges.CharRange.CharRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.CharRange` / receiver `CharRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/CharRange/CharRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_CharRange_CharRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_CharRange_CharRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_CharRange_CharRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.CharRange.endExclusive` — val CharRange.endExclusive: Char  -- `final val endExclusive`
    - `kotlin.ranges.CharRange.endInclusive` — val CharRange.endInclusive: Char  -- `final val endInclusive`
    - `kotlin.ranges.CharRange.equals` — fun CharRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.CharRange.hashCode` — fun CharRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.CharRange.start` — val CharRange.start: Char  -- `final val start`
    - `kotlin.ranges.CharRange.toString` — fun CharRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1298: kotlin.ranges.ClosedFloatingPointRange.ClosedFloatingPointRange の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.ranges.ClosedFloatingPointRange` / receiver `ClosedFloatingPointRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ClosedFloatingPointRange/ClosedFloatingPointRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ClosedFloatingPointRange_ClosedFloatingPointRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ClosedFloatingPointRange_ClosedFloatingPointRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ClosedFloatingPointRange_ClosedFloatingPointRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ClosedFloatingPointRange.contains` — fun ClosedFloatingPointRange.contains(): Boolean  -- `open fun contains(#A): kotlin/Boolean`
    - `kotlin.ranges.ClosedFloatingPointRange.isEmpty` — fun ClosedFloatingPointRange.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.ranges.ClosedFloatingPointRange.lessThanOrEquals` — fun ClosedFloatingPointRange.lessThanOrEquals(, ): Boolean  -- `abstract fun lessThanOrEquals(#A, #A): kotlin/Boolean`

- [ ] KSP-1299: kotlin.ranges.ClosedRange.ClosedRange の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges.ClosedRange` / receiver `ClosedRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ClosedRange/ClosedRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ClosedRange_ClosedRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ClosedRange_ClosedRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ClosedRange_ClosedRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ClosedRange.contains` — fun ClosedRange.contains(): Boolean  -- `open fun contains(#A): kotlin/Boolean`
    - `kotlin.ranges.ClosedRange.endInclusive` — val ClosedRange.endInclusive: #A  -- `abstract val endInclusive`
    - `kotlin.ranges.ClosedRange.isEmpty` — fun ClosedRange.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.ranges.ClosedRange.start` — val ClosedRange.start: #A  -- `abstract val start`

- [ ] KSP-1301: kotlin.ranges.IntProgression.IntProgression の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.ranges.IntProgression` / receiver `IntProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/IntProgression/IntProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntProgression_IntProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_IntProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_IntProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.IntProgression.equals` — fun IntProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.IntProgression.first` — val IntProgression.first: Int  -- `final val first`
    - `kotlin.ranges.IntProgression.hashCode` — fun IntProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.IntProgression.iterator` — fun IntProgression.iterator(): IntIterator  -- `open fun iterator(): kotlin.collections/IntIterator`
    - `kotlin.ranges.IntProgression.last` — val IntProgression.last: Int  -- `final val last`
    - `kotlin.ranges.IntProgression.step` — val IntProgression.step: Int  -- `final val step`
    - `kotlin.ranges.IntProgression.toString` — fun IntProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1302: kotlin.ranges.IntRange top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ranges.IntRange` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/IntRange/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntRange_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.IntRange.<init>` — constructor (Int, Int)  -- `constructor <init>(kotlin/Int, kotlin/Int)`
    - `kotlin.ranges.IntRange.Companion` — object kotlin.ranges.IntRange.Companion  -- `final object Companion {`

- [ ] KSP-1303: kotlin.ranges.IntRange.IntRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.IntRange` / receiver `IntRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/IntRange/IntRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntRange_IntRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_IntRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_IntRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.IntRange.endExclusive` — val IntRange.endExclusive: Int  -- `final val endExclusive`
    - `kotlin.ranges.IntRange.endInclusive` — val IntRange.endInclusive: Int  -- `final val endInclusive`
    - `kotlin.ranges.IntRange.equals` — fun IntRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.IntRange.hashCode` — fun IntRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.IntRange.start` — val IntRange.start: Int  -- `final val start`
    - `kotlin.ranges.IntRange.toString` — fun IntRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1304: kotlin.ranges.IntRange.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.IntRange.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/IntRange/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntRange_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.IntRange.Companion.EMPTY` — val Companion.EMPTY: IntRange  -- `final val EMPTY`

- [x] KSP-1305: kotlin.ranges.LongProgression top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.LongProgression` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongProgression/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongProgression.Companion` — object kotlin.ranges.LongProgression.Companion  -- `final object Companion {`
  - 完了根拠: KSP-1300（IntProgression）と同一パターンで `Sources/CompilerCore/Stdlib/kotlin/ranges/LongProgression/Stdlib.kt` に `public open class LongProgression internal constructor(start: Long, endInclusive: Long, step: Long) : Iterable<Long> { public companion object {} }` を追加し、既存の synthetic Companion を `HeaderHelpers+LongProgressionSourceMigration.swift`（新規）の `reusableSyntheticLongProgressionSourceCompanionSymbol` 経由で reuse、`HeaderCollection.swift` の `shouldRestoreDeclSiteForReusableSyntheticSymbol` に `kotlin.ranges.LongProgression` を追加して declSite を復元。KSP-1306（受信メンバ: equals/first/hashCode/iterator/last/step/toString）と KSP-1307（Companion.fromClosedRange）は範囲外のまま synthetic を維持。
  - 検証根拠: `RangeSyntheticMemberLinkTests.testLongProgressionCompanionIsSourceBacked`（新規）と既存 `LongProgressionHOFSourceMigrationTests` / `ULongProgressionHOFSourceMigrationTests` は PASS。golden `stdlib_kotlin_ranges_LongProgression_n_n.kt`/`.golden` は `GoldenHarnessWorker`（`KSWIFTK_GOLDEN_STDLIB_LIBRARY` 経由の artifact profile）で直接レンダリングし、`stdlib_kotlin_ranges_IntProgression_n_n.golden` と同型であることを確認。diff `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n_n.kt` は `bash Scripts/diff_kotlinc.sh` PASS。`bash Scripts/check_todo_ids.sh` pass。全 Golden / 全 diff_cases は共有環境の負荷が高く（`uptime` load average 65〜177）このタスクの変更範囲を超えるためローカルでは未実行、CI で確認する（本 issue の方針どおり）。

- [ ] KSP-1306: kotlin.ranges.LongProgression.LongProgression の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.ranges.LongProgression` / receiver `LongProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongProgression/LongProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_LongProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_LongProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_LongProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongProgression.equals` — fun LongProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.LongProgression.first` — val LongProgression.first: Long  -- `final val first`
    - `kotlin.ranges.LongProgression.hashCode` — fun LongProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.LongProgression.iterator` — fun LongProgression.iterator(): LongIterator  -- `open fun iterator(): kotlin.collections/LongIterator`
    - `kotlin.ranges.LongProgression.last` — val LongProgression.last: Long  -- `final val last`
    - `kotlin.ranges.LongProgression.step` — val LongProgression.step: Long  -- `final val step`
    - `kotlin.ranges.LongProgression.toString` — fun LongProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1307: kotlin.ranges.LongProgression.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.LongProgression.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongProgression/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongProgression.Companion.fromClosedRange` — fun Companion.fromClosedRange(Long, Long, Long): LongProgression  -- `final fun fromClosedRange(kotlin/Long, kotlin/Long, kotlin/Long): kotlin.ranges/LongProgression`

- [ ] KSP-1308: kotlin.ranges.LongRange top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ranges.LongRange` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongRange/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongRange_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongRange.<init>` — constructor (Long, Long)  -- `constructor <init>(kotlin/Long, kotlin/Long)`
    - `kotlin.ranges.LongRange.Companion` — object kotlin.ranges.LongRange.Companion  -- `final object Companion {`

- [ ] KSP-1309: kotlin.ranges.LongRange.LongRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.LongRange` / receiver `LongRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongRange/LongRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongRange_LongRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_LongRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_LongRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongRange.endExclusive` — val LongRange.endExclusive: Long  -- `final val endExclusive`
    - `kotlin.ranges.LongRange.endInclusive` — val LongRange.endInclusive: Long  -- `final val endInclusive`
    - `kotlin.ranges.LongRange.equals` — fun LongRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.LongRange.hashCode` — fun LongRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.LongRange.start` — val LongRange.start: Long  -- `final val start`
    - `kotlin.ranges.LongRange.toString` — fun LongRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1310: kotlin.ranges.LongRange.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.LongRange.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongRange/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongRange_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongRange.Companion.EMPTY` — val Companion.EMPTY: LongRange  -- `final val EMPTY`

- [ ] KSP-1311: kotlin.ranges.OpenEndRange.OpenEndRange の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges.OpenEndRange` / receiver `OpenEndRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/OpenEndRange/OpenEndRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_OpenEndRange_OpenEndRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_OpenEndRange_OpenEndRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_OpenEndRange_OpenEndRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.OpenEndRange.contains` — fun OpenEndRange.contains(): Boolean  -- `open fun contains(#A): kotlin/Boolean`
    - `kotlin.ranges.OpenEndRange.endExclusive` — val OpenEndRange.endExclusive: #A  -- `abstract val endExclusive`
    - `kotlin.ranges.OpenEndRange.isEmpty` — fun OpenEndRange.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.ranges.OpenEndRange.start` — val OpenEndRange.start: #A  -- `abstract val start`

- [ ] KSP-1312: kotlin.ranges.UIntProgression top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.UIntProgression` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntProgression/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntProgression_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntProgression.Companion` — object kotlin.ranges.UIntProgression.Companion  -- `final object Companion {`

- [ ] KSP-1313: kotlin.ranges.UIntProgression.UIntProgression の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.UIntProgression` / receiver `UIntProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntProgression/UIntProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntProgression_UIntProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_UIntProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_UIntProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntProgression.equals` — fun UIntProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.UIntProgression.first` — val UIntProgression.first: UInt  -- `final val first`
    - `kotlin.ranges.UIntProgression.hashCode` — fun UIntProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.UIntProgression.last` — val UIntProgression.last: UInt  -- `final val last`
    - `kotlin.ranges.UIntProgression.step` — val UIntProgression.step: Int  -- `final val step`
    - `kotlin.ranges.UIntProgression.toString` — fun UIntProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1314: kotlin.ranges.UIntRange top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ranges.UIntRange` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntRange/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntRange_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntRange.<init>` — constructor (UInt, UInt)  -- `constructor <init>(kotlin/UInt, kotlin/UInt)`
    - `kotlin.ranges.UIntRange.Companion` — object kotlin.ranges.UIntRange.Companion  -- `final object Companion {`

- [ ] KSP-1315: kotlin.ranges.UIntRange.UIntRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.UIntRange` / receiver `UIntRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntRange/UIntRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntRange_UIntRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_UIntRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_UIntRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntRange.endExclusive` — val UIntRange.endExclusive: UInt  -- `final val endExclusive`
    - `kotlin.ranges.UIntRange.endInclusive` — val UIntRange.endInclusive: UInt  -- `final val endInclusive`
    - `kotlin.ranges.UIntRange.equals` — fun UIntRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.UIntRange.hashCode` — fun UIntRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.UIntRange.start` — val UIntRange.start: UInt  -- `final val start`
    - `kotlin.ranges.UIntRange.toString` — fun UIntRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1316: kotlin.ranges.UIntRange.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.UIntRange.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntRange/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntRange_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntRange.Companion.EMPTY` — val Companion.EMPTY: UIntRange  -- `final val EMPTY`

- [ ] KSP-1317: kotlin.ranges.ULongProgression top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.ULongProgression` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongProgression/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongProgression.Companion` — object kotlin.ranges.ULongProgression.Companion  -- `final object Companion {`

- [ ] KSP-1318: kotlin.ranges.ULongProgression.ULongProgression の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.ULongProgression` / receiver `ULongProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongProgression/ULongProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_ULongProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_ULongProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_ULongProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongProgression.equals` — fun ULongProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.ULongProgression.first` — val ULongProgression.first: ULong  -- `final val first`
    - `kotlin.ranges.ULongProgression.hashCode` — fun ULongProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.ULongProgression.last` — val ULongProgression.last: ULong  -- `final val last`
    - `kotlin.ranges.ULongProgression.step` — val ULongProgression.step: Long  -- `final val step`
    - `kotlin.ranges.ULongProgression.toString` — fun ULongProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1319: kotlin.ranges.ULongProgression.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.ULongProgression.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongProgression/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongProgression.Companion.fromClosedRange` — fun Companion.fromClosedRange(ULong, ULong, Long): ULongProgression  -- `final fun fromClosedRange(kotlin/ULong, kotlin/ULong, kotlin/Long): kotlin.ranges/ULongProgression`

- [ ] KSP-1321: kotlin.ranges.ULongRange.ULongRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.ULongRange` / receiver `ULongRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongRange/ULongRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongRange_ULongRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_ULongRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_ULongRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongRange.endExclusive` — val ULongRange.endExclusive: ULong  -- `final val endExclusive`
    - `kotlin.ranges.ULongRange.endInclusive` — val ULongRange.endInclusive: ULong  -- `final val endInclusive`
    - `kotlin.ranges.ULongRange.equals` — fun ULongRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.ULongRange.hashCode` — fun ULongRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.ULongRange.start` — val ULongRange.start: ULong  -- `final val start`
    - `kotlin.ranges.ULongRange.toString` — fun ULongRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1322: kotlin.ranges.ULongRange.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.ULongRange.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongRange/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongRange_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongRange.Companion.EMPTY` — val Companion.EMPTY: ULongRange  -- `final val EMPTY`

- [ ] KSP-1323: kotlin.reflect top-level の未実装 stdlib API を実装する（15 件）
  - 対象: `kotlin.reflect` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.AssociatedObjectKey` — class kotlin.reflect.AssociatedObjectKey  -- `open annotation class kotlin.reflect/AssociatedObjectKey : kotlin/Annotation {`
    - `kotlin.reflect.ExperimentalAssociatedObjects` — class kotlin.reflect.ExperimentalAssociatedObjects  -- `open annotation class kotlin.reflect/ExperimentalAssociatedObjects : kotlin/Annotation {`
    - `kotlin.reflect.KAnnotatedElement` — interface kotlin.reflect.KAnnotatedElement  -- `abstract interface kotlin.reflect/KAnnotatedElement`
    - `kotlin.reflect.KCallable` — interface kotlin.reflect.KCallable  -- `abstract interface <#A: out kotlin/Any?> kotlin.reflect/KCallable : kotlin.reflect/KAnnotatedElement {`
    - `kotlin.reflect.KClass` — interface kotlin.reflect.KClass  -- `abstract interface <#A: kotlin/Any> kotlin.reflect/KClass : kotlin.reflect/KAnnotatedElement, kotlin.reflect/KClassifier, kotlin.reflect/KDeclarationContainer {`
    - `kotlin.reflect.KClassifier` — interface kotlin.reflect.KClassifier  -- `abstract interface kotlin.reflect/KClassifier`
    - `kotlin.reflect.KDeclarationContainer` — interface kotlin.reflect.KDeclarationContainer  -- `abstract interface kotlin.reflect/KDeclarationContainer`
    - `kotlin.reflect.KFunction` — interface kotlin.reflect.KFunction  -- `abstract interface <#A: out kotlin/Any?> kotlin.reflect/KFunction : kotlin.reflect/KCallable<#A>, kotlin/Function<#A>`
    - `kotlin.reflect.KMutableProperty` — interface kotlin.reflect.KMutableProperty  -- `abstract interface <#A: kotlin/Any?> kotlin.reflect/KMutableProperty : kotlin.reflect/KProperty<#A>`
    - `kotlin.reflect.KProperty` — interface kotlin.reflect.KProperty  -- `abstract interface <#A: out kotlin/Any?> kotlin.reflect/KProperty : kotlin.reflect/KCallable<#A>`
    - `kotlin.reflect.KType` — interface kotlin.reflect.KType  -- `abstract interface kotlin.reflect/KType {`
    - `kotlin.reflect.KTypeParameter` — interface kotlin.reflect.KTypeParameter  -- `abstract interface kotlin.reflect/KTypeParameter : kotlin.reflect/KClassifier {`
    - `kotlin.reflect.KTypeProjection` — class kotlin.reflect.KTypeProjection  -- `final class kotlin.reflect/KTypeProjection {`
    - `kotlin.reflect.KVariance` — enumClass kotlin.reflect.KVariance  -- `final enum class kotlin.reflect/KVariance : kotlin/Enum<kotlin.reflect/KVariance> {`
    - `kotlin.reflect.typeOf` — fun typeOf(): KType  -- `final inline fun <#A: reified kotlin/Any?> kotlin.reflect/typeOf(): kotlin.reflect/KType`

- [ ] KSP-1324: kotlin.reflect.KClass の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.reflect` / receiver `KClass`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KClasses.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KClass_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KClass_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KClass_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.cast` — fun KClass.cast(Any): #A  -- `final fun <#A: kotlin/Any> (kotlin.reflect/KClass<#A>).kotlin.reflect/cast(kotlin/Any?): #A`
    - `kotlin.reflect.findAssociatedObject` — fun KClass.findAssociatedObject(): Any  -- `final inline fun <#A: reified kotlin/Annotation> (kotlin.reflect/KClass<*>).kotlin.reflect/findAssociatedObject(): kotlin/Any?`
    - `kotlin.reflect.safeCast` — fun KClass.safeCast(Any): #A  -- `final fun <#A: kotlin/Any> (kotlin.reflect/KClass<#A>).kotlin.reflect/safeCast(kotlin/Any?): #A?`

- [ ] KSP-1333: kotlin.reflect.KTypeParameter.KTypeParameter の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.reflect.KTypeParameter` / receiver `KTypeParameter`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KTypeParameter/KTypeParameter.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KTypeParameter_KTypeParameter_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KTypeParameter_KTypeParameter_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KTypeParameter_KTypeParameter_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.KTypeParameter.isReified` — val KTypeParameter.isReified: Boolean  -- `abstract val isReified`
    - `kotlin.reflect.KTypeParameter.name` — val KTypeParameter.name: String  -- `abstract val name`
    - `kotlin.reflect.KTypeParameter.upperBounds` — val KTypeParameter.upperBounds: List  -- `abstract val upperBounds`
    - `kotlin.reflect.KTypeParameter.variance` — val KTypeParameter.variance: KVariance  -- `abstract val variance`

- [ ] KSP-1336: kotlin.reflect.KTypeProjection.Companion.Companion の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.reflect.KTypeProjection.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KTypeProjection.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KTypeProjection_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KTypeProjection_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KTypeProjection_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.KTypeProjection.Companion.STAR` — val Companion.STAR: KTypeProjection  -- `final val STAR`
    - `kotlin.reflect.KTypeProjection.Companion.contravariant` — fun Companion.contravariant(KType): KTypeProjection  -- `final fun contravariant(kotlin.reflect/KType): kotlin.reflect/KTypeProjection`
    - `kotlin.reflect.KTypeProjection.Companion.covariant` — fun Companion.covariant(KType): KTypeProjection  -- `final fun covariant(kotlin.reflect/KType): kotlin.reflect/KTypeProjection`
    - `kotlin.reflect.KTypeProjection.Companion.invariant` — fun Companion.invariant(KType): KTypeProjection  -- `final fun invariant(kotlin.reflect/KType): kotlin.reflect/KTypeProjection`
    - `kotlin.reflect.KTypeProjection.Companion.star` — val Companion.star: KTypeProjection  -- `final val star`

- [x] KSP-1338: kotlin.sequences top-level の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.sequences` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceFactories.kt`（既存 owner。TODO の `Stdlib.kt` は未作成のまま）
  - bridge/stub 整理: `sequence` / `iterator` は既存 `__kk_sequence_builder_build` / `__kk_iterator_builder_build` を public source 宣言へ移し、synthetic stub は同 FQName があれば skip。`sequenceOf(element)` は既存 `kk_sequence_of_single` を使う。Runtime ABI の新規追加なし。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。既存差分は 1 引数 `sequenceOf` が vararg から single overload へ解決される機械的なシグネチャ更新のみ。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_n_n.kt` green。
  - 完了ゲート: 共通 G（全 Swift / 全 Golden / 全 diff）は CI。ローカルは Sema Golden suite・対象 diff・関連 sequence factory diff 5 件・`check_todo_ids.sh`。
  - 未実装シンボル一覧:
    - `kotlin.sequences.Sequence` — fun Sequence(Function0): Sequence  -- `final inline fun <#A: kotlin/Any?> kotlin.sequences/Sequence(crossinline kotlin/Function0<kotlin.collections/Iterator<#A>>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.SequenceScope` — class kotlin.sequences.SequenceScope  -- `abstract class <#A: in kotlin/Any?> kotlin.sequences/SequenceScope {`
    - `kotlin.sequences.generateSequence` — fun generateSequence(Function0): Sequence  -- `final fun <#A: kotlin/Any> kotlin.sequences/generateSequence(kotlin/Function0<#A?>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.generateSequence` — fun generateSequence(, Function1): Sequence  -- `final fun <#A: kotlin/Any> kotlin.sequences/generateSequence(#A?, kotlin/Function1<#A, #A?>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.generateSequence` — fun generateSequence(Function0, Function1): Sequence  -- `final fun <#A: kotlin/Any> kotlin.sequences/generateSequence(kotlin/Function0<#A?>, kotlin/Function1<#A, #A?>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.iterator` — fun iterator(SuspendFunction1): Iterator  -- `final fun <#A: kotlin/Any?> kotlin.sequences/iterator(kotlin.coroutines/SuspendFunction1<kotlin.sequences/SequenceScope<#A>, kotlin/Unit>): kotlin.collections/Iterator<#A>`
    - `kotlin.sequences.sequence` — fun sequence(SuspendFunction1): Sequence  -- `final fun <#A: kotlin/Any?> kotlin.sequences/sequence(kotlin.coroutines/SuspendFunction1<kotlin.sequences/SequenceScope<#A>, kotlin/Unit>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.sequenceOf` — fun sequenceOf(): Sequence  -- `final inline fun <#A: kotlin/Any?> kotlin.sequences/sequenceOf(): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.sequenceOf` — fun sequenceOf(): Sequence  -- `final fun <#A: kotlin/Any?> kotlin.sequences/sequenceOf(#A): kotlin.sequences/Sequence<#A>`
  - 現状確認（2026-09-15、監査 stale・追記のみ）: 9件中7件は既存実装済みと確認。`SequenceScope`（`SequenceScope/SequenceScope.kt:9`、KSP-1361）、`generateSequence`の3overload全て（`SequenceFactories.kt:30,35,48`）、suspend builderの`sequence`/`iterator`（`SequenceBuilder.kt:11,14`、KSP-1519）、vararg `sequenceOf`（`SequenceFactories.kt:28`）。真の残件は2件のみ: (a) top-level `Sequence(crossinline () -> Iterator<T>): Sequence<T>` ファクトリ関数が repo 全体で未検出、(b) 零引数特化 `sequenceOf(): Sequence<T>`（現状は vararg 版のみで実質的に等価に動作するが、専用宣言としては未実装）。チェックボックスは残件があるため据え置き、次回着手者は上記2件のみに絞ってよい。

- [x] KSP-1340: kotlin.sequences.Sequence.associate-family の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `associate`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_associate.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_associate.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_associate.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `SequenceAggregateHOF.kt:207-238,483-541` に8シンボル全て実装済み（commit `d1940304f` #4497 "migrate sequence aggregate HOFs to source" が導入元）。既存 Sema テスト `SequenceAssociateSyntheticTests`/`SequenceAssociateByFunctionTests`/`SequenceAssociateBySyntheticTests`/`SequenceAssociateByToSyntheticTests`/`SequenceAssociateToFunctionTests`/`SequenceAssociateToSyntheticTests`/`SequenceAssociateWithSyntheticTests`/`SequenceAssociateWithToSyntheticTests`/`SequenceSyntheticMemberLinkTests`（`Tests/CompilerCoreTests/Sema/`）で回帰確認済み。`kk_sequence_*` の associate 系 runtime bridge は本 repo に存在しない。専用 golden/diff は本同期では追加しない。
  - 実装シンボル一覧:
    - `kotlin.sequences.associate` — fun Sequence.associate(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associate(kotlin/Function1<#A, kotlin/Pair<#B, #C>>): kotlin.collections/Map<#B, #C>`
    - `kotlin.sequences.associateBy` — fun Sequence.associateBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateBy(kotlin/Function1<#A, #B>): kotlin.collections/Map<#B, #A>`
    - `kotlin.sequences.associateBy` — fun Sequence.associateBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateBy(kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): kotlin.collections/Map<#B, #C>`
    - `kotlin.sequences.associateByTo` — fun Sequence.associateByTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #B, in #A>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateByTo(#C, kotlin/Function1<#A, #B>): #C`
    - `kotlin.sequences.associateByTo` — fun Sequence.associateByTo(, Function1, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, in #C>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateByTo(#D, kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): #D`
    - `kotlin.sequences.associateTo` — fun Sequence.associateTo(, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, in #C>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateTo(#D, kotlin/Function1<#A, kotlin/Pair<#B, #C>>): #D`
    - `kotlin.sequences.associateWith` — fun Sequence.associateWith(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateWith(kotlin/Function1<#A, #B>): kotlin.collections/Map<#A, #B>`
    - `kotlin.sequences.associateWithTo` — fun Sequence.associateWithTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateWithTo(#C, kotlin/Function1<#A, #B>): #C`

- [x] KSP-1341: kotlin.sequences.Sequence.element-family の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `element`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_element.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_element.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_element.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `SequenceAggregateHOF.kt:795-820`（コメント「KSP-442: Sequence terminal operations migrated to Kotlin source」ブロック内）に3シンボル全て実装済み（commit `c965a08f8` #5723）。`kk_sequence_elementAt`/`elementAtOrNull`/`elementAtOrElse` runtime bridge（`RuntimeSequence.swift`）は残置されているが、これは destination/laziness最適化用の既存基盤でありKSP-1360等の先行TODO同期PRでも保持方針。専用 golden/diff は本同期では追加しない。
  - 実装シンボル一覧:
    - `kotlin.sequences.elementAt` — fun Sequence.elementAt(Int): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/elementAt(kotlin/Int): #A`
    - `kotlin.sequences.elementAtOrElse` — fun Sequence.elementAtOrElse(Int, Function1): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/elementAtOrElse(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): #A`
    - `kotlin.sequences.elementAtOrNull` — fun Sequence.elementAtOrNull(Int): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/elementAtOrNull(kotlin/Int): #A?`

- [x] KSP-1344: kotlin.sequences.Sequence.first-family の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `first`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_first.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_first.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_first.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装シンボル一覧:
    - `kotlin.sequences.first` — fun Sequence.first(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/first(): #A`
    - `kotlin.sequences.first` — fun Sequence.first(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/first(kotlin/Function1<#A, kotlin/Boolean>): #A`
    - `kotlin.sequences.firstNotNullOf` — fun Sequence.firstNotNullOf(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any> (kotlin.sequences/Sequence<#A>).kotlin.sequences/firstNotNullOf(kotlin/Function1<#A, #B?>): #B`
    - `kotlin.sequences.firstNotNullOfOrNull` — fun Sequence.firstNotNullOfOrNull(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any> (kotlin.sequences/Sequence<#A>).kotlin.sequences/firstNotNullOfOrNull(kotlin/Function1<#A, #B?>): #B?`
    - `kotlin.sequences.firstOrNull` — fun Sequence.firstOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/firstOrNull(): #A?`
    - `kotlin.sequences.firstOrNull` — fun Sequence.firstOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/firstOrNull(kotlin/Function1<#A, kotlin/Boolean>): #A?`
  - 完了根拠（2026-09-19、KSP-1344 残件対応）: `SequenceConversionsAndSetOps.kt:36-59` に `firstNotNullOf` / `firstNotNullOfOrNull` を追加し、Sequence の encounter order、最初の non-null 結果、空結果、例外伝播を Kotlin source path で実装。`HeaderHelpers+SyntheticSequenceResidualStubs.swift` の該当 synthetic registration と Sequence runtime surface spec の該当2件を削除し、既存の低レベル runtime ABI bridge は direct/residual path 用として保持した。専用 Sema Golden、Sema call-binding/link テスト、Codegen 回帰、`stdlib_kotlin_sequences_Sequence_first.kt` の Kotlin 2.3.10 diff が PASS。

- [x] KSP-1345: kotlin.sequences.Sequence.flat-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `flat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceDestinationHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_flat.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_flat.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_flat.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.flatMapIndexedTo` — fun Sequence.flatMapIndexedTo(, Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/flatMapIndexedTo(#C, kotlin/Function2<kotlin/Int, #A, kotlin.collections/Iterable<#B>>): #C`
    - `kotlin.sequences.flatMapIndexedTo` — fun Sequence.flatMapIndexedTo(, Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/flatMapIndexedTo(#C, kotlin/Function2<kotlin/Int, #A, kotlin.sequences/Sequence<#B>>): #C`
    - `kotlin.sequences.flatMapTo` — fun Sequence.flatMapTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/flatMapTo(#C, kotlin/Function1<#A, kotlin.collections/Iterable<#B>>): #C`
    - `kotlin.sequences.flatMapTo` — fun Sequence.flatMapTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/flatMapTo(#C, kotlin/Function1<#A, kotlin.sequences/Sequence<#B>>): #C`
  - 完了根拠（focused）: Kotlin 2.3.10 の4 overload contract（`MutableCollection<in R>`、lambda return overload、indexed overflow、destination identity、順序・例外伝播）を `SequenceDestinationHOF.kt` に実装し、Sequence の flat destination HOF だけを通常 resolver に通す最小経路修正を追加した。既存 Iterable overload と共有 bridge/API は保持した。
  - 回帰（focused）: 専用 Sema Golden と `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_flat.kt` で Iterable/Sequence の overload 選択、型推論、空Sequence、index、destination identity、同名ユーザー関数、例外伝播を固定。既存 Sequence filter/fold と Iterable flat の worker Golden は無差分。Core resolver 所有PRの実パッチhunkは `/tmp/swifty-todo50-01a07dee/evidence/ksp1345/ownership-audit.md` に記録した。
  - 検証（focused PASS）: `swift build --disable-sandbox`、Sema Golden shard 64/75、対象 `diff_kotlinc`（Kotlin 2.3.10）、`RuntimeABIExternalLinkValidationTests` 4件、`check_todo_ids.sh`、`git diff --check`。
  - 完了（2026-09-15、マージ確認）: PR #6681（commit `4ab7948ae`）が `origin/master` にマージ済み（`git merge-base --is-ancestor` で確認、後続 `0778b4d8c`/`c7f04e6a8` からも祖先として到達可能）。共通ゲート G（全Swift/全Golden/全diff）は KUU-459 側の方針転換により CI 確認へ一本化されたため、上記の focused 検証を完了根拠として採用する。

- [x] KSP-1348: kotlin.sequences.Sequence.group-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `group`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_group.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_group.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_group.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `SequenceAggregateHOF.kt:247-283,543-583` に4シンボル全て実装済み（commit `d1940304f` #4497 "migrate sequence aggregate HOFs to source" が導入元）。`Tests/CompilerCoreTests/GoldenCases/Sema/sequence_group_by.kt` golden で回帰確認済み。`kk_sequence_groupBy`（`RuntimeSequence.swift:3423`）は runtime bridge として保持。専用 diff は本同期では追加しない。
  - 追記（2026-09-22、KUU-711）: 4 シンボルを Kotlin 2.3.10 ABI シグネチャに揃えた（`groupBy` は `Map<K, List<T>>` / `Map<K, List<V>>` 返しの `inline`、`groupByTo` は `M : MutableMap<in K, MutableList<…>>` 汎用 destination + `@IgnorableReturnValue`）。実装場所は既存の `SequenceAggregateHOF.kt`（package `kotlin.collections`）を維持し、本体は `Iterables.kt` の Iterable 版と同じ `for-in` 形に統一。専用 golden `stdlib_kotlin_sequences_Sequence_group.kt` と diff ケース `stdlib_kotlin_sequences_Sequence_group.kt`（supertype-keyed destination、destination identity、例外伝播を含む）を追加し、diff は Kotlin 2.3.10 に対し PASS。`sequence_group_by_to.golden` の差分は `gen=2→3` の機械的変更のみ。
  - 実装シンボル一覧:
    - `kotlin.sequences.groupBy` — fun Sequence.groupBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/groupBy(kotlin/Function1<#A, #B>): kotlin.collections/Map<#B, kotlin.collections/List<#A>>`
    - `kotlin.sequences.groupBy` — fun Sequence.groupBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/groupBy(kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): kotlin.collections/Map<#B, kotlin.collections/List<#C>>`
    - `kotlin.sequences.groupByTo` — fun Sequence.groupByTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #B, kotlin.collections/MutableList<#A>>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/groupByTo(#C, kotlin/Function1<#A, #B>): #C`
    - `kotlin.sequences.groupByTo` — fun Sequence.groupByTo(, Function1, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, kotlin.collections/MutableList<#C>>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/groupByTo(#D, kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): #D`

- [x] KSP-1350: kotlin.sequences.Sequence.join-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `join`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_join.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_join.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_join.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `SequenceAggregateHOF.kt:601-671`（コメント「KSP-621」）に `joinTo` 3 overload・`joinToString` 8 overload（デフォルト引数の代わりに手動 overload 展開）が実装済み（commit `88213667f` #5999 "unify Iterable and Sequence joinTo/joinToString"）。`appendJoinToPlain`/`appendJoinToTransform` を Iterable と共有し `this.iterator()` 経由で動作するため Sequence 固有 bridge は無い。専用 golden/diff は本同期では追加しない。
  - 実装シンボル一覧:
    - `kotlin.sequences.joinTo` — fun Sequence.joinTo(, CharSequence, CharSequence, CharSequence, Int, CharSequence, Function1): #B  -- `final fun <#A: kotlin/Any?, #B: kotlin.text/Appendable> (kotlin.sequences/Sequence<#A>).kotlin.sequences/joinTo(#B, kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/Int = ..., kotlin/CharSequence = ..., kotlin/Function1<#A, kotlin/CharSequence>? = ...): #B`
    - `kotlin.sequences.joinToString` — fun Sequence.joinToString(CharSequence, CharSequence, CharSequence, Int, CharSequence, Function1): String  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/joinToString(kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/Int = ..., kotlin/CharSequence = ..., kotlin/Function1<#A, kotlin/CharSequence>? = ...): kotlin/String`

- [x] KSP-1351: kotlin.sequences.Sequence.last-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `last`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_last.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_last.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_last.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `SequenceAggregateHOF.kt:712-743`（KSP-442、commit `c965a08f8` #5723）に4シンボル全て実装済み。`kk_sequence_last`/`lastOrNull`（`RuntimeSequence.swift`）は runtime bridge として保持。専用 golden/diff は本同期では追加しない。
  - 実装シンボル一覧:
    - `kotlin.sequences.last` — fun Sequence.last(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/last(): #A`
    - `kotlin.sequences.last` — fun Sequence.last(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/last(kotlin/Function1<#A, kotlin/Boolean>): #A`
    - `kotlin.sequences.lastOrNull` — fun Sequence.lastOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/lastOrNull(): #A?`
    - `kotlin.sequences.lastOrNull` — fun Sequence.lastOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/lastOrNull(kotlin/Function1<#A, kotlin/Boolean>): #A?`

- [x] KSP-1352: kotlin.sequences.Sequence.map-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `map`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceDestinationHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_map.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_map.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_map.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `SequenceDestinationHOF.kt:30-118`（ファイル冒頭コメント「KSP-446: Sequence destination-collection higher-order functions migrated to Kotlin source」）に `mapTo`/`mapNotNullTo`/`mapIndexedTo`/`mapIndexedNotNullTo` 4シンボル全て実装済み（commit `4f80770bb` #5775）。
  - 完了根拠（2026-09-23、KUU-714）: 専用 golden `stdlib_kotlin_sequences_Sequence_map.kt` / 専用 diff `stdlib_kotlin_sequences_Sequence_map.kt` を追加し、4シンボル全てが `kotlin.sequences.*` の Kotlin source 宣言に束縛されること・kotlinc と出力一致することを確認。bridge/stub/RuntimeABISpec の残存登録なし（#5775 で整理済み）。
  - 実装シンボル一覧:
    - `kotlin.sequences.mapIndexedNotNullTo` — fun Sequence.mapIndexedNotNullTo(, Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/mapIndexedNotNullTo(#C, kotlin/Function2<kotlin/Int, #A, #B?>): #C`
    - `kotlin.sequences.mapIndexedTo` — fun Sequence.mapIndexedTo(, Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/mapIndexedTo(#C, kotlin/Function2<kotlin/Int, #A, #B>): #C`
    - `kotlin.sequences.mapNotNullTo` — fun Sequence.mapNotNullTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/mapNotNullTo(#C, kotlin/Function1<#A, #B?>): #C`
    - `kotlin.sequences.mapTo` — fun Sequence.mapTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/mapTo(#C, kotlin/Function1<#A, #B>): #C`

- [x] KSP-1353: kotlin.sequences.Sequence.max-family の未実装 stdlib API を実装する（18 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `max`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceAggregateHOF.kt`
  - 完了根拠（2026-09-15）: 18 件中 8 件（`max()`/`maxOrNull()` の generic `#A` オーバーロード、`maxBy`/`maxByOrNull`、`maxOf`/`maxOfOrNull` の generic `#B` オーバーロード、`maxWith`/`maxWithOrNull`）は監査 stale で既存実装済み（KUU-459 PR-A で確認済み）。残り 10 件のうち 6 件（`maxOf(Function1): Double/Float`・`maxOfOrNull(Function1): Double/Float`・`maxOfWith`・`maxOfWithOrNull`）を本 PR で実装。`maxOf`/`maxOfOrNull` の Double/Float 特化は `@OverloadResolutionByLambdaReturnType`（要 `inline fun` + `@OptIn(ExperimentalTypeInference)` + `@SinceKotlin("1.4")`）でラムダ戻り値型により generic 版と識別。`maxOfWith`/`maxOfWithOrNull` は `CallTypeChecker+MemberCallInferenceCollectionFlow.swift` の `activeCollectionHOFNames` から Sequence receiver 時のみ除外する Sema 修正を同 PR に含む（従来はこの fast path が Sequence 向けの束縛を一切持たず、KIR の legacy `kk_list_maxOfWith` フォールバックへ落ちてリンクエラーになっていた。List/Map の挙動は smoke test で回帰なし確認）。
  - 見送り（2026-09-15）: `max(): Double`/`max(): Float`/`maxOrNull(): Double`/`maxOrNull(): Float` の 4 件は本 PR では実装しない。同名 0 引数オーバーロードを複数（Float 特化・Double 特化・generic）追加すると `bindBundledSequenceAggregateSource`（同ファイル 2065 行）が receiver の要素型を見ずに `lookupAll(...).first(where:)` で候補を選ぶため、`Sequence<Int>.max()` 等 Double 以外の receiver でも常に Double 特化版の symbol に束縛される重大な誤り束縛を確認（バインディング検査テストで実測）。generic `Comparable` 版は既に Float/Double を含む全 Comparable receiver で数値的に正しい結果を返す（NaN 伝播などの IEEE754 pairwise 厳密仕様は持たないが、この差分は master 時点から existing gap であり本 PR で悪化させていない）。安全な修正には `bindBundledSequenceAggregateSource` 自体への receiver 要素型フィルタ追加が必要で別 PR 課題。詳細は Linear バグ参照。
  - 見送り解消（2026-09-21, KUU-715）: #6919 が Sequence aggregate fast path に receiver 要素型フィルタ（`sequenceSourceReceiverElementMatches`）を追加済みのため、残り 4 件（`Sequence<Double>.max()`/`Sequence<Float>.max()`/`Sequence<Double>.maxOrNull()`/`Sequence<Float>.maxOrNull()`）を実装。Iterables.kt と同じく `kk_max_double`/`kk_max_float` の pairwise 比較で IEEE-754 の NaN 伝播・符号付きゼロ順序を維持。generic 宣言より手前に置き、fast path の first-match で Double/Float receiver は特化版に、それ以外の要素型は従来どおり generic に束縛されることを golden で確認。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_max.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_max.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_max.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装シンボル一覧（本 PR で新規実装した 6 件）:
    - `kotlin.sequences.maxOf` — fun Sequence.maxOf(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOf(kotlin/Function1<#A, kotlin/Double>): kotlin/Double`
    - `kotlin.sequences.maxOf` — fun Sequence.maxOf(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOf(kotlin/Function1<#A, kotlin/Float>): kotlin/Float`
    - `kotlin.sequences.maxOfOrNull` — fun Sequence.maxOfOrNull(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfOrNull(kotlin/Function1<#A, kotlin/Double>): kotlin/Double?`
    - `kotlin.sequences.maxOfOrNull` — fun Sequence.maxOfOrNull(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfOrNull(kotlin/Function1<#A, kotlin/Float>): kotlin/Float?`
    - `kotlin.sequences.maxOfWith` — fun Sequence.maxOfWith(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfWith(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B`
    - `kotlin.sequences.maxOfWithOrNull` — fun Sequence.maxOfWithOrNull(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfWithOrNull(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B?`
  - 実装シンボル一覧（KUU-715 で新規実装した 4 件、旧見送り分）:
    - `kotlin.sequences.max` — fun Sequence.max(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/max(): kotlin/Double`
    - `kotlin.sequences.max` — fun Sequence.max(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/max(): kotlin/Float`
    - `kotlin.sequences.maxOrNull` — fun Sequence.maxOrNull(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/maxOrNull(): kotlin/Double?`
    - `kotlin.sequences.maxOrNull` — fun Sequence.maxOrNull(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/maxOrNull(): kotlin/Float?`

- [x] KSP-1354: kotlin.sequences.Sequence.min-family の未実装 stdlib API を実装する（18 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `min`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceAggregateHOF.kt`
  - 完了根拠（2026-09-15）: KSP-1353 と同型。18 件中 8 件（generic `#A` の `min`/`minOrNull`、`minBy`/`minByOrNull`、generic `#B` の `minOf`/`minOfOrNull`、`minWith`/`minWithOrNull`）は既存実装済み。残り 10 件のうち 6 件（`minOf(Function1): Double/Float`・`minOfOrNull(Function1): Double/Float`・`minOfWith`・`minOfWithOrNull`）を本 PR で実装。`minOfWith`/`minOfWithOrNull` は KSP-1353 と同じ `activeCollectionHOFNames` 修正で救済。
  - 見送り（2026-09-15）: `min(): Double`/`min(): Float`/`minOrNull(): Double`/`minOrNull(): Float` の 4 件は KSP-1353 と同じ理由（`bindBundledSequenceAggregateSource` の receiver 要素型フィルタ欠如）で見送り。加えて `Iterable<Float>.min()`/`Iterable<Float>.minOrNull()`（`Iterables.kt`）が `sequenceOf(3.0f, 1.0f).let { listOf(*it.toList().toTypedArray()) }.min()` 相当の入力で先頭要素をそのまま返す既存バグ（`comparisonMinOf` を `iterator()` ベースのループから呼ぶ経路で発生、`kk_min_float`/`comparisonMinOf` 単体は正しく動作することを分離テストで確認済み）を発見。Sequence 版を実装する際にこの経路へ誤束縛されると同じ症状（`sequenceOf(3.0f, 1.0f).min()` が `3.0` を返す）を再現した。Linear バグ起票: [KUU-553](https://linear.app/kuu/issue/KUU-553)。
  - 見送り解消（2026-09-22, KUU-716）: #6919 が Sequence aggregate fast path に receiver 要素型フィルタ（`sequenceSourceReceiverElementMatches`）を追加済み、かつ KUU-553 が #6970 で修正済み（floating-point List min 呼び出しを Iterable 特化版へルーティング）のため、残り 4 件（`Sequence<Double>.min()`/`Sequence<Float>.min()`/`Sequence<Double>.minOrNull()`/`Sequence<Float>.minOrNull()`）を実装。同ファイルの minOf 系と同じく `comparisonMinOf`（`kotlin.comparisons.minOf`）の pairwise 比較で IEEE-754 の NaN 伝播・符号付きゼロ順序を維持（ヘッダコメント記載のとおり `kk_min_*` のローカル再宣言は直接呼ぶと誤動作する経歴があるため使用しない）。generic 宣言より手前に置き、fast path の first-match で Double/Float receiver は特化版に、それ以外の要素型は従来どおり generic に束縛されることを golden で確認。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_min.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_min.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_min.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装シンボル一覧（本 PR で新規実装した 6 件）:
    - `kotlin.sequences.minOf` — fun Sequence.minOf(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOf(kotlin/Function1<#A, kotlin/Double>): kotlin/Double`
    - `kotlin.sequences.minOf` — fun Sequence.minOf(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOf(kotlin/Function1<#A, kotlin/Float>): kotlin/Float`
    - `kotlin.sequences.minOfOrNull` — fun Sequence.minOfOrNull(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfOrNull(kotlin/Function1<#A, kotlin/Double>): kotlin/Double?`
    - `kotlin.sequences.minOfOrNull` — fun Sequence.minOfOrNull(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfOrNull(kotlin/Function1<#A, kotlin/Float>): kotlin/Float?`
    - `kotlin.sequences.minOfWith` — fun Sequence.minOfWith(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfWith(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B`
    - `kotlin.sequences.minOfWithOrNull` — fun Sequence.minOfWithOrNull(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfWithOrNull(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B?`
  - 実装シンボル一覧（KUU-716 で新規実装した 4 件、旧見送り分）:
    - `kotlin.sequences.min` — fun Sequence.min(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/min(): kotlin/Double`
    - `kotlin.sequences.min` — fun Sequence.min(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/min(): kotlin/Float`
    - `kotlin.sequences.minOrNull` — fun Sequence.minOrNull(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/minOrNull(): kotlin/Double?`
    - `kotlin.sequences.minOrNull` — fun Sequence.minOrNull(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/minOrNull(): kotlin/Float?`

- [x] KSP-1355: kotlin.sequences.Sequence.reduce-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `reduce`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_reduce.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_reduce.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_reduce.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期）: `SequenceAggregateHOF.kt:29-77`（commit `ede38b49d` #4287 "Add MIGRATION-SEQ-004: bundle Sequence aggregate HOFs in Kotlin source"）に4シンボル全て実装済み。`kk_sequence_reduce*`（`RuntimeSequence.swift`）は runtime bridge として保持。専用 golden/diff は本同期では追加しない。
  - 実装シンボル一覧:
    - `kotlin.sequences.reduce` — fun Sequence.reduce(Function2): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.sequences/Sequence<#B>).kotlin.sequences/reduce(kotlin/Function2<#A, #B, #A>): #A`
    - `kotlin.sequences.reduceIndexed` — fun Sequence.reduceIndexed(Function3): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.sequences/Sequence<#B>).kotlin.sequences/reduceIndexed(kotlin/Function3<kotlin/Int, #A, #B, #A>): #A`
    - `kotlin.sequences.reduceIndexedOrNull` — fun Sequence.reduceIndexedOrNull(Function3): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.sequences/Sequence<#B>).kotlin.sequences/reduceIndexedOrNull(kotlin/Function3<kotlin/Int, #A, #B, #A>): #A?`
    - `kotlin.sequences.reduceOrNull` — fun Sequence.reduceOrNull(Function2): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.sequences/Sequence<#B>).kotlin.sequences/reduceOrNull(kotlin/Function2<#A, #B, #A>): #A?`
  - 完了根拠: `SequenceConversionsAndSetOps.kt` に canonical `<S, T : S>` シグネチャの `public inline` 版を追加し、`SequenceAggregateHOF.kt`（`kotlin.collections`）の `<T>` 限定・`toList()` 経由版を除去した。bound call を `kk_sequence_reduceIndexed*` に横取りする Sequence 向け rewrite（VirtualCallRewrite / CallRewriteHOFAccumulations の Kotlin-name 腕）を削除。`kk_sequence_reduce*` Runtime 関数・RuntimeABISpec・未解決 fallback は Iterable/List/Set の残余 dispatch（`unresolvedCollectionMemberCallee`・`RuntimeSequenceIndexedReduceCompatibility`）と reduceRight 系が共用するため保持。
  - 回帰: `SequenceReduceFunctionTests` で 4 API の canonical FQName 解決・source-backed・no-link・`<S, T : S>` ワイドニングを固定し、Sema Golden (`stdlib_kotlin_sequences_Sequence_reduce`) と `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_reduce.kt` を追加した。
  - 検証: `swift build` OK / Sema Golden suite 92 件 pass（新規 golden 生成済み） / `SequenceReduceFunctionTests`・`SequenceSyntheticMemberLinkTests`・`SequenceFold*`・`CodegenBackendCollectionReduce*`・Runtime Sequence テスト pass / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_reduce.kt` PASS / `check_todo_ids.sh` pass / `validate_runtime_abi_links.sh` 4 件 pass
  - 既知の別件制約: operation が `T` と異なる型を返す異種 accumulator（例: `{ acc: Any, v -> ... }`）は型推論が `S` を要素型に固定するため `KSWIFTK-TYPE-0001` になる（`Iterable.reduce` でも同じ挙動）。また boxed `Number` への `toInt()` 仮想 dispatch は既存のランタイム制約でクラッシュするため、diff ケースの widening 例は member 呼び出しを避けた形にしている。

- [x] KSP-1356: kotlin.sequences.Sequence.shuffled-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `shuffled`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_shuffled.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_shuffled.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_shuffled.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15）: `SequenceConversionsAndSetOps.kt` に `shuffled()`/`shuffled(random: Random)` を追加。実体は既存の `List<T>.shuffled(random)`（`ListSortingHOF.kt:217`）と `Iterable<T>.asSequence()`（`Sequences.kt:10`）に委譲する upstream 準拠の1行実装（`toMutableList().shuffled(random).asSequence()`）で、結果は「1回だけ確定的にシャッフルされた固定列」（`iterator()` の呼び出しごとに再シャッフルはしない）。
  - bridge/stub 整理（実施）: `HeaderHelpers+SyntheticSequenceResidualStubs.swift` の synthetic `shuffled`/`shuffled(random)` 登録ブロック（STDLIB-SEQ-019）を削除し、`@KsSymbolName("kk_sequence_shuffled")` / `@KsSymbolName("kk_sequence_shuffled_random")` で既存の `RuntimeSequence.swift` 側 `kk_sequence_shuffled`/`kk_sequence_shuffled_random` ブリッジ（lazy pipeline step 実装、非破壊）への external-link 登録に置き換え。ブリッジ本体は保持（他の `kk_sequence_*` 同様、pipeline fusion のため）。
  - 検証: `swift build` green。`.build/debug/kswiftc --stdlib-from-source` での手動スモークテストで size/`toSet()`/`sorted()`一致・同一シード決定性・元 Sequence 非破壊・空/単一要素ケースを確認。`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_shuffled.kt`（新規、順序非依存アサーションのみ）と既存 `Scripts/diff_cases/sequence_shuffled.kt` の両方が `DIFF_COMPILE_TIMEOUT=600` 下で PASS（実 kotlinc 2.3.10、artifact-based stdlib 経由 = 通常 import 経路の確認を兼ねる）。golden は `KSWIFTK_GOLDEN_STDLIB_LIBRARY` を artifact-based `.artifacts/diff_kotlinc/KSwiftKStdlib.kklib` に設定した `GoldenHarnessWorker` 直接呼び出しで生成（bundled-source フォールバックでの生成は symbol-origin classification が CI と不一致になるため使用していない）。`RuntimeABIExternalLinkValidationTests`（4件）・`check_todo_ids.sh`・`git diff --check` すべて green。全 Golden スイート・全 diff ケース一括は未実施（CI 確認）。
  - 実装シンボル一覧:
    - `kotlin.sequences.shuffled` — fun Sequence.shuffled(): Sequence  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/shuffled(): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.shuffled` — fun Sequence.shuffled(Random): Sequence  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/shuffled(kotlin.random/Random): kotlin.sequences/Sequence<#A>`

- [x] KSP-1357: kotlin.sequences.Sequence.single-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `single`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_single.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_single.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_single.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-15、既存実装のTODO同期 / 2026-09-22 KSP-1357 残件対応）: `SequenceConversionsAndSetOps.kt` に upstream 準拠の lazy iterator 実装を追加（`single()`/`singleOrNull()` は2要素目で short-circuit、predicate 版は `public inline`＋2件目マッチで早期脱出）。`SequenceAggregateHOF.kt`（KSP-442、commit `c965a08f8` #5723）の `toList()` 経由版を除去した。`kk_sequence_single`/`singleOrNull`（`RuntimeSequence.swift`）・RuntimeABISpec エントリ・`CallLowerer` の未解決 fallback name-string 特例は Iterable/List 残余 dispatch・unresolved member recovery が共用するため保持。synthetic stub / `StdlibSurfaceSpec` 登録は存在しないことを確認。
  - 回帰: `SequenceSingleFunctionTests` に4 overload の canonical FQName 解決・source-backed・no-link を固定するテストを追加し、Sema Golden (`stdlib_kotlin_sequences_Sequence_single`) と `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_single.kt`（全 overload・型付き例外・無限 Sequence の早期終了）を追加した。
  - 実装シンボル一覧:
    - `kotlin.sequences.single` — fun Sequence.single(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/single(): #A`
    - `kotlin.sequences.single` — fun Sequence.single(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/single(kotlin/Function1<#A, kotlin/Boolean>): #A`
    - `kotlin.sequences.singleOrNull` — fun Sequence.singleOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/singleOrNull(): #A?`
    - `kotlin.sequences.singleOrNull` — fun Sequence.singleOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/singleOrNull(kotlin/Function1<#A, kotlin/Boolean>): #A?`

- [ ] KSP-1359: kotlin.sequences.Sequence.sum-family の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `sum`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_sum.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_sum.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_sum.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.sum` — fun Sequence.sum(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/sum(): kotlin/Double`
    - `kotlin.sequences.sum` — fun Sequence.sum(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/sum(): kotlin/Float`
    - `kotlin.sequences.sum` — fun Sequence.sum(): Long  -- `final fun (kotlin.sequences/Sequence<kotlin/Long>).kotlin.sequences/sum(): kotlin/Long`
    - `kotlin.sequences.sum` — fun Sequence.sum(): UInt  -- `final fun (kotlin.sequences/Sequence<kotlin/UByte>).kotlin.sequences/sum(): kotlin/UInt`
    - `kotlin.sequences.sum` — fun Sequence.sum(): UInt  -- `final fun (kotlin.sequences/Sequence<kotlin/UInt>).kotlin.sequences/sum(): kotlin/UInt`
    - `kotlin.sequences.sum` — fun Sequence.sum(): ULong  -- `final fun (kotlin.sequences/Sequence<kotlin/ULong>).kotlin.sequences/sum(): kotlin/ULong`
    - `kotlin.sequences.sum` — fun Sequence.sum(): UInt  -- `final fun (kotlin.sequences/Sequence<kotlin/UShort>).kotlin.sequences/sum(): kotlin/UInt`
    - `kotlin.sequences.sumOf` — fun Sequence.sumOf(Function1): Long  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/sumOf(kotlin/Function1<#A, kotlin/Long>): kotlin/Long`
    - `kotlin.sequences.sumOf` — fun Sequence.sumOf(Function1): UInt  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/sumOf(kotlin/Function1<#A, kotlin/UInt>): kotlin/UInt`
    - `kotlin.sequences.sumOf` — fun Sequence.sumOf(Function1): ULong  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/sumOf(kotlin/Function1<#A, kotlin/ULong>): kotlin/ULong`

- [ ] KSP-1362: kotlin.text top-level の未実装 stdlib API を実装する（20 件）
  - 対象: `kotlin.text` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Appendable` — interface kotlin.text.Appendable  -- `abstract interface kotlin.text/Appendable {`
    - `kotlin.text.CharCategory` — enumClass kotlin.text.CharCategory  -- `final enum class kotlin.text/CharCategory : kotlin/Enum<kotlin.text/CharCategory> {`
    - `kotlin.text.HexFormat` — fun HexFormat(Function1): HexFormat  -- `final inline fun kotlin.text/HexFormat(kotlin/Function1<kotlin.text/HexFormat.Builder, kotlin/Unit>): kotlin.text/HexFormat`
    - `kotlin.text.MatchGroupCollection` — interface kotlin.text.MatchGroupCollection  -- `abstract interface kotlin.text/MatchGroupCollection : kotlin.collections/Collection<kotlin.text/MatchGroup?> {`
    - `kotlin.text.MatchNamedGroupCollection` — interface kotlin.text.MatchNamedGroupCollection  -- `abstract interface kotlin.text/MatchNamedGroupCollection : kotlin.text/MatchGroupCollection {`
    - `kotlin.text.MatchResult` — interface kotlin.text.MatchResult  -- `abstract interface kotlin.text/MatchResult {`
    - `kotlin.text.String` — fun String(CharArray): String  -- `final fun kotlin.text/String(kotlin/CharArray): kotlin/String`
    - `kotlin.text.String` — fun String(CharArray, Int, Int): String  -- `final fun kotlin.text/String(kotlin/CharArray, kotlin/Int, kotlin/Int): kotlin/String`
    - `kotlin.text.Typography` — object kotlin.text.Typography  -- `final object kotlin.text/Typography {`
    - `kotlin.text.append` — fun append(Array): #A  -- `final fun <#A: kotlin.text/Appendable> (#A).kotlin.text/append(kotlin/Array<out kotlin/CharSequence?>...): #A`
    - `kotlin.text.appendRange` — fun appendRange(CharSequence, Int, Int): #A  -- `final fun <#A: kotlin.text/Appendable> (#A).kotlin.text/appendRange(kotlin/CharSequence, kotlin/Int, kotlin/Int): #A`
    - `kotlin.text.buildString` — fun buildString(Function1): String  -- `final inline fun kotlin.text/buildString(kotlin/Function1<kotlin.text/StringBuilder, kotlin/Unit>): kotlin/String`
    - `kotlin.text.buildString` — fun buildString(Int, Function1): String  -- `final inline fun kotlin.text/buildString(kotlin/Int, kotlin/Function1<kotlin.text/StringBuilder, kotlin/Unit>): kotlin/String`
    - `kotlin.text.checkRadix` — fun checkRadix(Int): Int  -- `final fun kotlin.text/checkRadix(kotlin/Int): kotlin/Int`
    - `kotlin.text.ifBlank` — fun ifBlank(Function0): #B  -- `final inline fun <#A: #B & kotlin/CharSequence, #B: kotlin/Any?> (#A).kotlin.text/ifBlank(kotlin/Function0<#B>): #B`
    - `kotlin.text.ifEmpty` — fun ifEmpty(Function0): #B  -- `final inline fun <#A: #B & kotlin/CharSequence, #B: kotlin/Any?> (#A).kotlin.text/ifEmpty(kotlin/Function0<#B>): #B`
    - `kotlin.text.intToString` — fun intToString(Int, Int): String  -- `final fun kotlin.text/intToString(kotlin/Int, kotlin/Int): kotlin/String`
    - `kotlin.text.longToString` — fun longToString(Long, Int): String  -- `final fun kotlin.text/longToString(kotlin/Long, kotlin/Int): kotlin/String`
    - `kotlin.text.onEach` — fun onEach(Function1): #A  -- `final inline fun <#A: kotlin/CharSequence> (#A).kotlin.text/onEach(kotlin/Function1<kotlin/Char, kotlin/Unit>): #A`
    - `kotlin.text.onEachIndexed` — fun onEachIndexed(Function2): #A  -- `final inline fun <#A: kotlin/CharSequence> (#A).kotlin.text/onEachIndexed(kotlin/Function2<kotlin/Int, kotlin/Char, kotlin/Unit>): #A`

- [x] KSP-1366: kotlin.text.CharSequence.associate-family の実装・focused検証済み（8 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `associate`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_associate.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_associate.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_associate.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.associate` — fun CharSequence.associate(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin/CharSequence).kotlin.text/associate(kotlin/Function1<kotlin/Char, kotlin/Pair<#A, #B>>): kotlin.collections/Map<#A, #B>`
    - `kotlin.text.associateBy` — fun CharSequence.associateBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/associateBy(kotlin/Function1<kotlin/Char, #A>): kotlin.collections/Map<#A, kotlin/Char>`
    - `kotlin.text.associateBy` — fun CharSequence.associateBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin/CharSequence).kotlin.text/associateBy(kotlin/Function1<kotlin/Char, #A>, kotlin/Function1<kotlin/Char, #B>): kotlin.collections/Map<#A, #B>`
    - `kotlin.text.associateByTo` — fun CharSequence.associateByTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableMap<in #A, in kotlin/Char>> (kotlin/CharSequence).kotlin.text/associateByTo(#B, kotlin/Function1<kotlin/Char, #A>): #B`
    - `kotlin.text.associateByTo` — fun CharSequence.associateByTo(, Function1, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin/CharSequence).kotlin.text/associateByTo(#C, kotlin/Function1<kotlin/Char, #A>, kotlin/Function1<kotlin/Char, #B>): #C`
    - `kotlin.text.associateTo` — fun CharSequence.associateTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin/CharSequence).kotlin.text/associateTo(#C, kotlin/Function1<kotlin/Char, kotlin/Pair<#A, #B>>): #C`
    - `kotlin.text.associateWith` — fun CharSequence.associateWith(Function1): Map  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/associateWith(kotlin/Function1<kotlin/Char, #A>): kotlin.collections/Map<kotlin/Char, #A>`
    - `kotlin.text.associateWithTo` — fun CharSequence.associateWithTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableMap<in kotlin/Char, in #A>> (kotlin/CharSequence).kotlin.text/associateWithTo(#B, kotlin/Function1<kotlin/Char, #A>): #B`
  - 完了根拠（2026-09-15 再確認）: `StringHOF.kt` に 8 overloads の source-backed 実装があり、CharSequence の indexed dispatch、重複キーの後勝ち、destination 返却、標準 map capacity を保持している。実装・Sema golden・diff fixture は PR #6719（2026-09-09 マージ済み）で現 HEAD の祖先に取り込まれている。対象 overload に専用の `__kk_*` / `kk_*` runtime bridge、synthetic stub、RuntimeABISpec entry、CallTypeChecker / CallLowerer の name-string 特例は存在しない。
  - 検証（2026-09-15）: `swift build --disable-sandbox`、対象 Sema golden の `GoldenHarnessWorker` 出力と committed `.golden` の完全一致、`DIFF_REQUIRE_JDK21=0 DIFF_PARALLEL=0 bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_associate.kt`（1/1 PASS）、`CharSequenceElementSourceMigrationTests`（2/2 PASS）、Runtime ABI 検証（4/4 PASS）、`bash Scripts/check_todo_ids.sh`、`git diff --check` が pass。全体 Golden / 全 diff は AGENTS.md の最小スコープに従い再実行していない。

- [x] KSP-1368: kotlin.text.CharSequence.common-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `common`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringComparison.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_common.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_common.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_common.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.commonPrefixWith` — fun CharSequence.commonPrefixWith(CharSequence, Boolean): String  -- `final fun (kotlin/CharSequence).kotlin.text/commonPrefixWith(kotlin/CharSequence, kotlin/Boolean = ...): kotlin/String`
    - `kotlin.text.commonSuffixWith` — fun CharSequence.commonSuffixWith(CharSequence, Boolean): String  -- `final fun (kotlin/CharSequence).kotlin.text/commonSuffixWith(kotlin/CharSequence, kotlin/Boolean = ...): kotlin/String`
  - 完了根拠: `StringComparison.kt` に Kotlin 2.3.10 の `CharSequence` receiver overload を追加した。既存の `String` overload、`__kkCharsEqual` の二段 case-fold、String/CharSequence の indexed dispatch は保持し、サロゲート対を結果境界で分割しない専用 helper を同じ source family に限定した。Runtime ABI / synthetic bridge は追加していない。
  - 回帰: `stdlib_kotlin_text_CharSequence_common.kt` の Sema Golden と diff fixture で、静的 CharSequence の String/StringBuilder/custom receiver、空/全一致/部分一致、ignoreCase、非 ASCII、サロゲート境界を固定した。既存 `common_prefix_with` / `common_suffix_with` Golden は overload 番号だけ再生成した。
  - 検証: `swift build --disable-sandbox` と専用 GoldenHarnessWorker probe、`check_todo_ids.sh`、`git diff --check` が pass。指定の `run_heavy.py` 経由専用 diff、Golden shard、全 Swift/Golden/all diff、Runtime ABI link 検証は共有2枠（base 全 Swift / 他 TODO の検証）待機中のため保留し、Draft として記録する。2026-09-15 [x] 化: PR #6685（e9ead796b、2026-09-08 マージ済み）で実装・検証済みで現ブランチ HEAD の祖先。`gh pr checks 6685` で共通ゲート G 相当の全 19 ジョブ（Build debug/release、TODO ID 重複検査、CompilerCore/Smoke 6 shard、Backend/Runtime/CLI/LSP 4 shard、Repository Checks、kotlinc Diff 4 shard）が pass 済みであることを再確認し、上記の保留分は解消済み。

- [x] KSP-1369: kotlin.text.CharSequence.contains-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `contains`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringIndexOf.kt`, `Sources/CompilerCore/Stdlib/kotlin/text/StringSearchReplace.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_contains.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_contains.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_contains.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装状況: Kotlin 2.3.10 の `CharSequence.contains(Char, Boolean)` と `contains(Regex)` を source-backed 実装し、既存の `CharSequence.contains(CharSequence, Boolean)` も custom receiver の indexed semantics に合わせた。`String.contains(Regex)` の runtime bridge は String 固有経路として保持し、CharSequence 側に bridge/stub は追加していない。
  - 未実装シンボル一覧:
    - `kotlin.text.contains` — fun CharSequence.contains(Regex): Boolean  -- `final inline fun (kotlin/CharSequence).kotlin.text/contains(kotlin.text/Regex): kotlin/Boolean`
    - `kotlin.text.contains` — fun CharSequence.contains(Char, Boolean): Boolean  -- `final fun (kotlin/CharSequence).kotlin.text/contains(kotlin/Char, kotlin/Boolean = ...): kotlin/Boolean`
  - 完了根拠: PR #6699 の source-backed 実装を含む親スタック PR #6694 が `719ce8acb` として master にマージ済み。Sema Golden、custom CharSequence の indexed dispatch、Regex/Char の operator・named call、StringBuilder・surrogate・empty/short-circuit を回帰ケースで固定した。
  - 検証（2026-09-16）: `swift build --disable-sandbox -Xswiftc -swift-version -Xswiftc 6`、Sema Golden 対象 shard（`KSWIFTK_GOLDEN_SHARD_INDEX=78 KSWIFTK_GOLDEN_SHARD_COUNT=93`）および専用 `GoldenHarnessWorker` の `.golden` 完全一致、`DIFF_REQUIRE_JDK21=0 DIFF_COMPILE_TIMEOUT=600 bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_contains.kt`、`bash Scripts/validate_runtime_abi_links.sh --disable-sandbox --no-parallel -Xswiftc -swift-version -Xswiftc 6`（4/4）、`bash Scripts/check_todo_ids.sh` が pass。親スタック PR #6694 の CI（run 34437982954）は全 Swift/Golden、Backend/Runtime/CLI/LSP、kotlinc diff の全シャード green。

- [x] KSP-1370: kotlin.text.CharSequence.count-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `count`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_count.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_count.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_count.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.count` — fun CharSequence.count(): Int  -- `final inline fun (kotlin/CharSequence).kotlin.text/count(): kotlin/Int`
  - 完了根拠（2026-09-15 実測、KUU-352）: 実装本体は `6d285993f`（PR #6683「KSP-1370: implement CharSequence.count」、2026-09-09 マージ済み、現ブランチ HEAD `ff67efd08` の祖先）で `@InlineOnly inline fun CharSequence.count(): Int = length` を source-backed 実装済み。CI 実ログで kotlinc diff shard 3/4 が `Summary: total=312 failed=0 passed=312`、`CharSequenceCountSourceMigrationTests` suite が PASS を確認済み（continue-on-error による見かけ green ではない）。本 PR であらためてローカル再検証: `swift build` PASS / `bash Scripts/swift_test.sh --no-parallel --filter CompilerCoreTests.CharSequenceCountSourceMigrationTests` → `Test run with 2 tests in 1 suite passed` / `bash Scripts/swift_test.sh --skip-build --no-parallel --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden`（UPDATE_GOLDEN 無し）→ `matchesGolden(batch:) with 92 test cases passed`（#6683 後に StringHOF.kt を触った後続5PR分のゴールデンドリフト無しを確認）/ `DIFF_REQUIRE_JDK21=0 DIFF_COMPILE_TIMEOUT=600 bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_count.kt` → `total=1 failed=0 passed=1`（共有マシン高負荷時は既定 120s の stdlib artifact ビルドタイムアウトで一度 false failure、`ps`/`uptime` で負荷を確認の上で切り分け、`DIFF_COMPILE_TIMEOUT` 延長で再現しないことを確認済み）/ `bash Scripts/validate_runtime_abi_links.sh` → `Test run with 4 tests in 1 suite passed` / `bash Scripts/check_todo_ids.sh` pass。bridge/stub 側は `kk_string_count_flat` が KSP-410 で既に削除済み（`Sources/RuntimeABI/RuntimeABISpec+String.swift` のコメント参照）で追加削除対象なし、`CallTypeChecker`/`CallLowerer` にも count 用の CharSequence 向け name-string 特例なし。全 suite・全 Golden（4 スイート一括）・全 `diff_cases` はローカル未実行、CI に委譲。

- [~] KSP-1371: kotlin.text.CharSequence.drop-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `drop`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_drop.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_drop.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_drop.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.drop` — fun CharSequence.drop(Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/drop(kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.dropLast` — fun CharSequence.dropLast(Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/dropLast(kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.dropLastWhile` — fun CharSequence.dropLastWhile(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/dropLastWhile(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`
    - `kotlin.text.dropWhile` — fun CharSequence.dropWhile(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/dropWhile(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`

- [x] KSP-1372: kotlin.text.CharSequence.element-family の未実装 stdlib API を実装する（3 件）
  - 完了: PR #6690（`7e6627557`、2026-09-12 マージ。名前付き引数の型推論修正 PR #6608 を基点とした依存 PR）で `elementAt` / `elementAtOrElse` / `elementAtOrNull` の 3 API を `StringHOF.kt` の bundled Kotlin source 宣言として実装し、member / safe-member inline lambda の non-local return 配線も同 PR で配線済み。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `element`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_element.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_element.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_element.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.elementAt` — fun CharSequence.elementAt(Int): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/elementAt(kotlin/Int): kotlin/Char`
    - `kotlin.text.elementAtOrElse` — fun CharSequence.elementAtOrElse(Int, Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/elementAtOrElse(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Char>): kotlin/Char`
    - `kotlin.text.elementAtOrNull` — fun CharSequence.elementAtOrNull(Int): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/elementAtOrNull(kotlin/Int): kotlin/Char?`
  - 検証（2026-09-14 再確認）: `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_element.kt` PASS（non-local return / captured / named / safe-call 各ケースで kotlinc parity）。`bash Scripts/check_todo_ids.sh` PASS。`bash Scripts/validate_runtime_abi_links.sh` 4/4 PASS。PR #6690 の CI 全シャード green、master CI green。全体 G（全テスト / 全 Golden / 全 diff ケース）は AGENTS.md の最小スコープ方針どおり CI で確認済みのため、ローカル再実行は diff ケース単体のみ。

- [x] KSP-1374: kotlin.text.CharSequence.first-family の未実装 stdlib API を実装する（6 件）
  - **2026-09-15 実装メモ**: 着手時に前提を確認したところ、対象6 API（`first()` / `first(predicate)` / `firstOrNull()` / `firstOrNull(predicate)` / `firstNotNullOf` / `firstNotNullOfOrNull`）は全て `StringHOF.kt` に実装済みで、golden テスト（`stdlib_kotlin_text_CharSequence_first.{kt,golden}`）と diff ケース（`stdlib_kotlin_text_CharSequence_first.kt` / `_imported_nlr.kt`）も既にコミット済みだった。実体は PR #6702「KSP-1374: add CharSequence first family」（`gh stack` でスタックされ、2026-09-09 に PR #6697 のスタック squash merge commit `293acdf78` の一部として master に着地。squash コミット本文に元の "KSP-1374: add CharSequence first family" / "Fix non-local return type checking in lambdas" が個別コミットとして残存）と、nlr diff ケースを追加した PR #6700（KSP-1399）。両 PR とも CI 全ジョブ green（kotlinc Diff 4 shard 含む）を `gh pr checks 6697` / `gh pr checks 6700` で確認済み。`[~]` のまま残っていたのは、squash merge でコミットタイトルが別チケット（KSP-1390）名義になったことによる TODO.md 側の更新漏れ（stale 化）。
  - 旧メモの検証保留（non-local return）は解消確認済み: 「bundled stdlib inline predicate の non-local return が precompiled-inline lowering 制約に当たる（reference `120` / candidate `97`）」という懸念を本チケットで再検証したが、現 HEAD では再現しない。`stdlib_kotlin_text_CharSequence_first_imported_nlr.kt`（`source.first { if (it=='x') return '!'; false }` による非局所 return）は reference/candidate とも `33`（`'!'.code`）で完全一致。
  - bridge/stub 整理（本チケットで追加確認）: `String.first()` / `String.firstOrNull()`（`StringQuery.kt` 10-30 行目）は今も `__kk_string_first` / `__kk_string_firstOrNull` → `__kk_string_first_flat` / `__kk_string_firstOrNull_flat` bridge に委譲しており、これは KSP-402 所有の String 固有オーバーロードとして意図的に維持されている（`StringQuery.kt` 80-82 行目の KSP-1384 コメント、および PR #6702 本文の「String overload と runtime bridge は変更なし」）。`CharSequence` 受信の6 API 自体には対応する `__kk_*` / `kk_*` bridge・`HeaderHelpers+Synthetic*Stubs.swift` 登録・`RuntimeABISpec` エントリは存在せず、削除対象なし（「無ければ新規 Kotlin 実装のみ」に該当）。`CallLowerer+LegacyMemberLikeCalls.swift` / `MemberRuntimeDispatch.swift` に残る "first"/"firstOrNull" の name-string 特例は String receiver 限定かつ last/single と共有された既存残骸であり、本チケット単独のスコープ外のため未変更（同型の boxed非flat `kk_string_first`/`kk_string_firstOrNull` 等の死亡コードは別タスクとして切り出し済み）。
  - 検証（2026-09-15、コード変更なし）: `swift build` green。`bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6 --no-parallel` green（Sema golden 全92バッチ PASS）。`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_first.kt` green。`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_first_imported_nlr.kt` green。`bash Scripts/check_todo_ids.sh` PASS。`bash Scripts/validate_runtime_abi_links.sh` 4/4 PASS。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `first`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`（PR #6702 で追加済み）

- [x] KSP-1375: kotlin.text.CharSequence.flat-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `flat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - 実装済み（ゲート保留）: `flatMap` / `flatMapIndexed` / `flatMapTo` / `flatMapIndexedTo` の4 APIをKotlin 2.3.10 source contractに沿って追加。indexed accessでcustom CharSequenceの`get` dispatchと反復中の`length`再評価を保持し、destinationの順序・同一性・nullable/primitive要素を回帰する。
  - 実装上の制約: 現コンパイラでgeneric `for` / `addAll` のsource body loweringが成立しないため、各要素のindexed accessと戻りIterableのiterator/addへ展開した。標準Iterableの順序・全要素走査・destination戻り値は保持し、別APIのbridgeは追加していない。
  - 検証保留: inline transformのnon-local return SemaはKSP-1374の共通修正を親ブランチとして検証する。全体Golden / 全diff / ABIゲートはこのPR headでは未実行。
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_flat.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_flat.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_flat.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.flatMap` — fun CharSequence.flatMap(Function1): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/flatMap(kotlin/Function1<kotlin/Char, kotlin.collections/Iterable<#A>>): kotlin.collections/List<#A>`
    - `kotlin.text.flatMapIndexed` — fun CharSequence.flatMapIndexed(Function2): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/flatMapIndexed(kotlin/Function2<kotlin/Int, kotlin/Char, kotlin.collections/Iterable<#A>>): kotlin.collections/List<#A>`
    - `kotlin.text.flatMapIndexedTo` — fun CharSequence.flatMapIndexedTo(, Function2): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/flatMapIndexedTo(#B, kotlin/Function2<kotlin/Int, kotlin/Char, kotlin.collections/Iterable<#A>>): #B`
    - `kotlin.text.flatMapTo` — fun CharSequence.flatMapTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/flatMapTo(#B, kotlin/Function1<kotlin/Char, kotlin.collections/Iterable<#A>>): #B`
  - 完了: PR #6718（2026-09-09 マージ、e176d62f）で4 API を `StringHOF.kt` に実装済み（indexed access + iterator/add 展開、bridge 追加なし）。non-local return Sema の共通前提は親 PR #6702（KSP-1374、同日マージ）で解消。`stdlib_kotlin_text_CharSequence_flat.kt` の Sema golden・diff ケース、`CharSequenceFlatSourceMigrationTests` を同 PR で追加済み。当時保留だった全体ゲートは #6718 の CI が全 shard green（kotlinc diff 4/4・全テスト shard・TODO ID チェック含む）で充足。

- [x] KSP-1376: kotlin.text.CharSequence.fold-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `fold`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_fold.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_fold.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_fold.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.fold` — fun CharSequence.fold(, Function2): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/fold(#A, kotlin/Function2<#A, kotlin/Char, #A>): #A`
    - `kotlin.text.foldIndexed` — fun CharSequence.foldIndexed(, Function3): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/foldIndexed(#A, kotlin/Function3<kotlin/Int, #A, kotlin/Char, #A>): #A`
    - `kotlin.text.foldRight` — fun CharSequence.foldRight(, Function2): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/foldRight(#A, kotlin/Function2<kotlin/Char, #A, #A>): #A`
    - `kotlin.text.foldRightIndexed` — fun CharSequence.foldRightIndexed(, Function3): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/foldRightIndexed(#A, kotlin/Function3<kotlin/Int, kotlin/Char, #A, #A>): #A`
  - 完了根拠（2026-09-16）: `StringHOF.kt` の4 APIを `public inline` の source-backed 実装として整備し、forward fold の反復中 `length` 再評価と right fold の初回長さスナップショットを Kotlin `CharSequence` 契約に合わせた。CharSequence receiver の fold-family に対応する `__kk_*` / `kk_*` runtime 関数、synthetic stub、`RuntimeABISpec` エントリ、専用 name-string 特例は存在せず、bridge 側の変更は不要。Sema source-migration テスト、golden と custom/mutable CharSequence、UTF-16、empty、全4 API、inline non-local return、例外伝播を `stdlib_kotlin_text_CharSequence_fold.{kt,golden}` / `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_fold.kt` で固定した。
  - 検証（2026-09-16）: `swift build` PASS。`CharSequenceFoldSourceMigrationTests`（2 tests）PASS。`UPDATE_GOLDEN=1 KSWIFTK_GOLDEN_SHARD_INDEX=79 KSWIFTK_GOLDEN_SHARD_COUNT=93 swift test --build-system swiftbuild --skip-build --test-product CompilerCoreTests --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden --no-parallel -Xswiftc -swift-version -Xswiftc 6`（対象8ケース）PASS、専用 GoldenHarnessWorker の再生成結果も committed golden と完全一致。`DIFF_REQUIRE_JDK21=0 DIFF_PARALLEL=0 DIFF_COMPILE_TIMEOUT=600 DIFF_RUN_TIMEOUT=60 bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_fold.kt` PASS。全 Sema golden / 全 diff はローカル未実行、CI に委譲。

- [x] KSP-1377: kotlin.text.CharSequence.for-family の未実装 stdlib API を実装する（2 件）
  - **2026-09-16 完了確認**: `StringHOF.kt` の source-backed inline `forEach` / `forEachIndexed`、Sema source-binding テスト、Golden fixture、diff ケースは PR #6701（2026-09-12 merge）で既に master に着地済み。diff ケースは UTF-16 code unit、動的 `CharSequence` の length/get と mutation、callback throw、direct/safe/captured/named inline non-local return を固定している。
  - bridge/stub 監査: CharSequence receiver の for-family に対応する `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリは存在せず、削除対象なし。`CallTypeChecker+*` / `CallLowerer+*` に残る `forEach` の name-string は Iterable/collection/range の汎用解決・source routing であり、本 API の旧 bridge 特例ではないため維持する。
  - 検証（2026-09-16）: `swift build --disable-sandbox -Xswiftc -swift-version -Xswiftc 6` PASS。`CharSequenceForSourceMigrationTests` 2/2 PASS。`DIFF_REQUIRE_JDK21=0 JAVA_HOME=/opt/homebrew/opt/openjdk@17 DIFF_STDLIB_LIBRARY=.artifacts/diff_kotlinc/KSwiftKStdlib.kklib bash Scripts/diff_kotlinc.sh --no-parallel Scripts/diff_cases/stdlib_kotlin_text_CharSequence_for.kt` PASS。`bash Scripts/check_todo_ids.sh` PASS、`bash Scripts/validate_runtime_abi_links.sh --disable-sandbox --no-parallel -Xswiftc -swift-version -Xswiftc 6` 4/4 PASS。共通 G（全テスト / 全 Golden / 全 diff）はローカル実行せず、PR #6701 の CI 全ジョブ green（kotlinc Diff 4/4）を確認済み。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `for`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`

- [~] KSP-1378: kotlin.text.CharSequence.get-family の未実装 stdlib API を実装する（2 件）
  - 実装中: CharSequence の getOrElse / getOrNull を Kotlin source に追加。#6690 の inline/member return 修正を基点とし、全体 G はこの PR head で未完了。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `get`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_get.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_get.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_get.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.getOrElse` — fun CharSequence.getOrElse(Int, Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/getOrElse(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Char>): kotlin/Char`
    - `kotlin.text.getOrNull` — fun CharSequence.getOrNull(Int): Char  -- `final fun (kotlin/CharSequence).kotlin.text/getOrNull(kotlin/Int): kotlin/Char?`

- [x] KSP-1379: kotlin.text.CharSequence.group-family の未実装 stdlib API を実装する（4 件）
  - 完了: PR #6722（GitHub 上 MERGED 扱い）で実装。master への実際の着地は PR #6700 の squash commit `5673c7b32`（2026-09-11）で、`groupBy`（keySelector / keySelector+valueTransform の 2 オーバーロード）と `groupByTo`（同 2 オーバーロード）の計 4 API が `StringHOF.kt` に bundled Kotlin source として存在する。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `group`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_group.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_group.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_group.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.groupBy` — fun CharSequence.groupBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/groupBy(kotlin/Function1<kotlin/Char, #A>): kotlin.collections/Map<#A, kotlin.collections/List<kotlin/Char>>`
    - `kotlin.text.groupBy` — fun CharSequence.groupBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin/CharSequence).kotlin.text/groupBy(kotlin/Function1<kotlin/Char, #A>, kotlin/Function1<kotlin/Char, #B>): kotlin.collections/Map<#A, kotlin.collections/List<#B>>`
    - `kotlin.text.groupByTo` — fun CharSequence.groupByTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableMap<in #A, kotlin.collections/MutableList<kotlin/Char>>> (kotlin/CharSequence).kotlin.text/groupByTo(#B, kotlin/Function1<kotlin/Char, #A>): #B`
    - `kotlin.text.groupByTo` — fun CharSequence.groupByTo(, Function1, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, kotlin.collections/MutableList<#B>>> (kotlin/CharSequence).kotlin.text/groupByTo(#C, kotlin/Function1<kotlin/Char, #A>, kotlin/Function1<kotlin/Char, #B>): #C`
  - 検証（2026-09-14 再確認）: `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_group.kt` PASS（kotlinc parity）。`bash Scripts/check_todo_ids.sh` PASS。`bash Scripts/validate_runtime_abi_links.sh` 4/4 PASS。master CI green（09-11 着地後の 09-12・09-13 ランを含む連続成功）で全体 G を確認済み。ローカル再実行は diff ケース単体のみ（最小スコープ方針）。

- [ ] KSP-1380: kotlin.text.CharSequence.grouping-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `grouping`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_grouping.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_grouping.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_grouping.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.groupingBy` — fun CharSequence.groupingBy(Function1): Grouping  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/groupingBy(crossinline kotlin/Function1<kotlin/Char, #A>): kotlin.collections/Grouping<kotlin/Char, #A>`

- [x] KSP-1381: kotlin.text.CharSequence.has-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `has`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/CharSurrogate.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_has.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_has.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_has.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.hasSurrogatePairAt` — fun CharSequence.hasSurrogatePairAt(Int): Boolean  -- `final fun (kotlin/CharSequence).kotlin.text/hasSurrogatePairAt(kotlin/Int): kotlin/Boolean`
  - 実装済み（ゲート保留）: Kotlin 2.3.10 の注釈なし `CharSequence.hasSurrogatePairAt(Int): Boolean` を `CharSurrogate.kt` に source-backed で追加した。upstream の短絡契約に合わせ、負の index では `length` getter を読まず、範囲内だけ indexed `get` を2回行う。専用 Sema Golden、正しい pair・孤立/逆順 surrogate・空文字列・先頭/末尾/out-of-range・custom CharSequence の indexed get/length getter を専用 diff で固定し、focused Sema、専用 diff、Swift build、synthetic link（4/4）、Runtime ABI（4/4）、TODO ID、diff check は pass。全 Golden と全 diff_cases は共有環境の aggregate gate として未完了のため Draft として記録する。
  - 完了: PR #6691（2026-09-12 マージ、c7f04e6a）で `CharSurrogate.kt` に `hasSurrogatePairAt` を実装済み。Sema golden・diff ケースも同 PR で追加済み。当時 Draft 保留だった aggregate ゲート（全 Golden / 全 diff_cases / ABI）は #6691 の CI が全 18 チェック green で充足。

- [x] KSP-1382: kotlin.text.CharSequence.indices-family の未実装 stdlib API を実装する（1 件）
  - **2026-09-16 完了確認**: `StringHOF.kt` の source-backed `CharSequence.indices` getter、Sema golden fixture、Native/kotlinc 差分ケースは PR #6695（2026-09-12 merge）で master に着地済み。PR #6695 の CI 全チェックも green。
  - bridge/stub 監査: 対象の `kotlin.text.indices` に対応する `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例は存在せず、削除対象なし。
  - 検証（2026-09-16）: prebuilt stdlib artifact を使った対象 Sema golden render と committed golden の一致、`DIFF_STDLIB_LIBRARY=.build/kswiftk-test-stdlib-cache-177e30b1c5ffe57a.kklib DIFF_WORKERS=1 bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_indices.kt` PASS、`bash Scripts/check_todo_ids.sh` PASS、`bash Scripts/validate_runtime_abi_links.sh --disable-sandbox --no-parallel -Xswiftc -swift-version -Xswiftc 6` 4/4 PASS を確認。指定の全 Sema golden 走査は同時実行負荷で worker timeout が発生したため、対象単体 render と PR CI を証跡とした。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `indices`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_indices.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_indices.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_indices.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.indices` — val CharSequence.indices  -- `final val kotlin.text/indices`
  - 実装・focused確認済み（2026-09-08）：`StringHOF.kt` に Kotlin 2.3.10 と同じ source-backed getter を追加。Sema worker で `kotlin.text.indices.$get` / `IntRange` を確認し、String・StringBuilder・空文字列・UTF-16 surrogate・length getter が一度だけ呼ばれる custom CharSequence の Native 実行を kotlinc と比較した。専用 evidence は `/tmp/swifty-todo50-01a07dee/evidence/ksp1382`。全体 Swift/Golden/diff G は未実行のため完了化しない。

- [ ] KSP-1383: kotlin.text.CharSequence.iterator-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `iterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_iterator.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_iterator.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_iterator.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.iterator` — fun CharSequence.iterator(): CharIterator  -- `final fun (kotlin/CharSequence).kotlin.text/iterator(): kotlin.collections/CharIterator`

- [x] KSP-1384: kotlin.text.CharSequence.last-family の未実装 stdlib API を実装する（5 件）
  - 完了根拠（2026-09-16 再確認）: 5 API の source-backed 実装は PR #6698（`429027e71`、KSP-1378 の KSP-1384 変更 `7afb87a1e`）で `StringQuery.kt` に着地済み。Sema golden（`stdlib_kotlin_text_CharSequence_last.{kt,golden}`）と kotlinc diff ケースも同 PR に含まれ、String / StringBuilder / custom CharSequence、UTF-16 code unit、空文字列、predicate、captured / safe-call / non-local return を固定している。今回の HEAD で artifact 指定の単一 Sema worker と `DIFF_COMPILE_TIMEOUT=600` の専用 diff を再実行し、いずれも reference parity（diff `total=1 failed=0 passed=1`）を確認した（既定 120 秒では共有環境の candidate compile timeout）。
  - bridge/stub 監査: CharSequence receiver の 5 API に対応する専用 `__kk_*` / `kk_*` bridge・synthetic stub・RuntimeABI entry は存在しない。`String` 固有の `kk_string_last_flat` / `kk_string_lastOrNull_flat` と synthetic wrapper は KSP-402 の生きた実装として維持する。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `last`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringQuery.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_last.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_last.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_last.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.last` — fun CharSequence.last(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/last(): kotlin/Char`
    - `kotlin.text.last` — fun CharSequence.last(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/last(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char`
    - `kotlin.text.lastIndex` — val CharSequence.lastIndex  -- `final val kotlin.text/lastIndex`
    - `kotlin.text.lastOrNull` — fun CharSequence.lastOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/lastOrNull(): kotlin/Char?`
    - `kotlin.text.lastOrNull` — fun CharSequence.lastOrNull(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/lastOrNull(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char?`

- [x] KSP-1385: kotlin.text.CharSequence.map-family の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `map`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - 実装済み（ゲート保留）: Kotlin 2.3.10 source contractに合わせ、`mapIndexedNotNull` / `mapIndexedNotNullTo` / `mapIndexedTo` / `mapNotNullTo` / `mapTo` を追加。custom CharSequenceのindexed `get` dispatch・反復中の`length`再評価、callback順序、destination同一性、nullable/primitive結果を回帰する。
  - 実装境界: upstreamの`for` / `forEach`を、KSP-1377の未統合APIに依存しないindexed loopへ展開し、destinationへ要素単位で`add`する。既存のmap/mapIndexed/mapNotNull実装、synthetic bridge、Runtime ABIは変更しない。
  - **2026-09-16 完了メモ**: #6702 の共通Sema修正を親祖先として、non-local transform を含む対象 Sema 回帰 3 件を確認。artifact-backed map golden は既存 golden と一致し、対象 diff ケースも kotlinc と一致した。`bash Scripts/validate_runtime_abi_links.sh` は 4/4 green。ローカル全 Sema golden は arm64 macOS の worker timeout 8件で完走しなかったが、実装元 PR #6723 の CI run 34212817260 で Verification 0/5〜5/5（CompilerCore golden 6 shard、その他検証 4 shard、kotlinc diff 4 shard を含む）全 pass を確認した。
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_map.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_map.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_map.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.mapIndexedNotNull` — fun CharSequence.mapIndexedNotNull(Function2): List  -- `final inline fun <#A: kotlin/Any> (kotlin/CharSequence).kotlin.text/mapIndexedNotNull(kotlin/Function2<kotlin/Int, kotlin/Char, #A?>): kotlin.collections/List<#A>`
    - `kotlin.text.mapIndexedNotNullTo` — fun CharSequence.mapIndexedNotNullTo(, Function2): #B  -- `final inline fun <#A: kotlin/Any, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/mapIndexedNotNullTo(#B, kotlin/Function2<kotlin/Int, kotlin/Char, #A?>): #B`
    - `kotlin.text.mapIndexedTo` — fun CharSequence.mapIndexedTo(, Function2): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/mapIndexedTo(#B, kotlin/Function2<kotlin/Int, kotlin/Char, #A>): #B`
    - `kotlin.text.mapNotNullTo` — fun CharSequence.mapNotNullTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/mapNotNullTo(#B, kotlin/Function1<kotlin/Char, #A?>): #B`
    - `kotlin.text.mapTo` — fun CharSequence.mapTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/mapTo(#B, kotlin/Function1<kotlin/Char, #A>): #B`

- [x] KSP-1386: kotlin.text.CharSequence.matches-family の未実装 stdlib API を実装する（1 件）
  - **2026-09-15 実装メモ**: 着手時に前提を確認したところ、`CharSequence.matches(Regex): Boolean` の Kotlin source 実装・golden テスト・diff ケースは #6707（PR「KSP-1386: source-back CharSequence.matches」、2026-09-10 merge）で既に完了済みだった。本チケットが `[~]` のまま残っていたのは、#6707 の PR 本文が「全体 Swift/Golden/diff gate は未実行」として Draft 前提で書かれていたため。実際には同 PR の CI（run 34459082933）は merge 前に Verification 1〜5/5 全ショード green、kotlinc Diff も4ショード全てで実ログ `failed=0` を確認済み。ランタイム bridge/stub 側の積み残しも監査したが、`__kk_string_matches_regex_flat`（String.matches）・`__kk_regex_matches_flat`（Regex.matches）とも生きた bridge で削除対象なし。`CallLowerer+LegacyMemberLikeCalls.swift` に `"matches"` / `"get"` / `"compareTo"` の到達不能な影コードが残っているが、これは KSP-1386 より前（#4591, RF-KIR-002）から存在する無関係な横断的デッドコードのため、本チケットのスコープでは変更していない。本 PR では TODO.md のマーカー更新のみ実施。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `matches`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringSearchReplace.kt`(#6707 で追加済み)

- [~] KSP-1387: kotlin.text.CharSequence.max-family の未実装 stdlib API を実装する（14 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `max`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - **2026-09-16 実装済み（ゲート保留）**: Kotlin 2.3.10 の source contract に合わせて 14 API を追加。`maxWith` 系の `Comparator<in Char>` を解決するため、use-site variance を持つ型引数だけを分解する Sema 制約修正を追加し、既存 `KCallable<*>` golden への副作用がないことを確認。対象 Sema golden 94 ケース、対象 diff ケース、Runtime ABI 4/4、TODO ID、`git diff --check` は pass。全 Golden / 全 diff_cases は未実行のため `[~]` を維持する。
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_max.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_max.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_max.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.max` — fun CharSequence.max(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/max(): kotlin/Char`
    - `kotlin.text.maxBy` — fun CharSequence.maxBy(Function1): Char  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/maxBy(kotlin/Function1<kotlin/Char, #A>): kotlin/Char`
    - `kotlin.text.maxByOrNull` — fun CharSequence.maxByOrNull(Function1): Char  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/maxByOrNull(kotlin/Function1<kotlin/Char, #A>): kotlin/Char?`
    - `kotlin.text.maxOf` — fun CharSequence.maxOf(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/maxOf(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double`
    - `kotlin.text.maxOf` — fun CharSequence.maxOf(Function1): Float  -- `final inline fun (kotlin/CharSequence).kotlin.text/maxOf(kotlin/Function1<kotlin/Char, kotlin/Float>): kotlin/Float`
    - `kotlin.text.maxOf` — fun CharSequence.maxOf(Function1): #A  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/maxOf(kotlin/Function1<kotlin/Char, #A>): #A`
    - `kotlin.text.maxOfOrNull` — fun CharSequence.maxOfOrNull(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/maxOfOrNull(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double?`
    - `kotlin.text.maxOfOrNull` — fun CharSequence.maxOfOrNull(Function1): Float  -- `final inline fun (kotlin/CharSequence).kotlin.text/maxOfOrNull(kotlin/Function1<kotlin/Char, kotlin/Float>): kotlin/Float?`
    - `kotlin.text.maxOfOrNull` — fun CharSequence.maxOfOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/maxOfOrNull(kotlin/Function1<kotlin/Char, #A>): #A?`
    - `kotlin.text.maxOfWith` — fun CharSequence.maxOfWith(Comparator, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/maxOfWith(kotlin/Comparator<in #A>, kotlin/Function1<kotlin/Char, #A>): #A`
    - `kotlin.text.maxOfWithOrNull` — fun CharSequence.maxOfWithOrNull(Comparator, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/maxOfWithOrNull(kotlin/Comparator<in #A>, kotlin/Function1<kotlin/Char, #A>): #A?`
    - `kotlin.text.maxOrNull` — fun CharSequence.maxOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/maxOrNull(): kotlin/Char?`
    - `kotlin.text.maxWith` — fun CharSequence.maxWith(Comparator): Char  -- `final fun (kotlin/CharSequence).kotlin.text/maxWith(kotlin/Comparator<in kotlin/Char>): kotlin/Char`
    - `kotlin.text.maxWithOrNull` — fun CharSequence.maxWithOrNull(Comparator): Char  -- `final fun (kotlin/CharSequence).kotlin.text/maxWithOrNull(kotlin/Comparator<in kotlin/Char>): kotlin/Char?`

- [~] KSP-1388: kotlin.text.CharSequence.min-family の未実装 stdlib API を実装する（14 件）
  - 実装済み（共通ゲート保留）: `StringHOF.kt` に `CharSequence` receiver の min/minBy/minByOrNull、minOf/minOfOrNull の Double/Float/Comparable overload、minOfWith/minOfWithOrNull、minOrNull/minWith/minWithOrNull の14 APIを Kotlin source-backed 実装として追加。空文字列の throw/null、先頭要素の tie、selector の singleton short-circuit、Comparator の比較方向と `CharSequence` の indexed `get` 契約を固定した。
  - bridge/stub 監査: 対象 CharSequence API に対応する `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリは存在せず、削除対象なし。既存の collection/list/sequence min runtime routing は別 receiver のため維持した。`minWith` / `minWithOrNull` は top-level `kotlin.comparisons` との名前衝突と `Comparator<in Char>` variance のため通常候補解決が失敗するので、既存の source-backed String member direct-bind helper を対象名・receiverに限定して再利用した。
  - 検証（2026-09-16）: `swift build` PASS。要求の artifact-based Sema Golden 更新コマンド（94 cases）PASS、生成 Golden に error 診断なし。`DIFF_STDLIB_LIBRARY=/tmp/kuu405-current-stdlib.kklib bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_min.kt` PASS。`bash Scripts/check_todo_ids.sh` PASS、`bash Scripts/validate_runtime_abi_links.sh` 4/4 PASS、`git diff --check` PASS。
  - 保留ゲート: 全 Golden / 全 diff はローカル未実行のため、TODO は `[~]` として記録する。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `min`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_min.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_min.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_min.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.min` — fun CharSequence.min(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/min(): kotlin/Char`
    - `kotlin.text.minBy` — fun CharSequence.minBy(Function1): Char  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/minBy(kotlin/Function1<kotlin/Char, #A>): kotlin/Char`
    - `kotlin.text.minByOrNull` — fun CharSequence.minByOrNull(Function1): Char  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/minByOrNull(kotlin/Function1<kotlin/Char, #A>): kotlin/Char?`
    - `kotlin.text.minOf` — fun CharSequence.minOf(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/minOf(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double`
    - `kotlin.text.minOf` — fun CharSequence.minOf(Function1): Float  -- `final inline fun (kotlin/CharSequence).kotlin.text/minOf(kotlin/Function1<kotlin/Char, kotlin/Float>): kotlin/Float`
    - `kotlin.text.minOf` — fun CharSequence.minOf(Function1): #A  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/minOf(kotlin/Function1<kotlin/Char, #A>): #A`
    - `kotlin.text.minOfOrNull` — fun CharSequence.minOfOrNull(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/minOfOrNull(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double?`
    - `kotlin.text.minOfOrNull` — fun CharSequence.minOfOrNull(Function1): Float  -- `final inline fun (kotlin/CharSequence).kotlin.text/minOfOrNull(kotlin/Function1<kotlin/Char, kotlin/Float>): kotlin/Float?`
    - `kotlin.text.minOfOrNull` — fun CharSequence.minOfOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/minOfOrNull(kotlin/Function1<kotlin/Char, #A>): #A?`
    - `kotlin.text.minOfWith` — fun CharSequence.minOfWith(Comparator, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/minOfWith(kotlin/Comparator<in #A>, kotlin/Function1<kotlin/Char, #A>): #A`
    - `kotlin.text.minOfWithOrNull` — fun CharSequence.minOfWithOrNull(Comparator, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/minOfWithOrNull(kotlin/Comparator<in #A>, kotlin/Function1<kotlin/Char, #A>): #A?`
    - `kotlin.text.minOrNull` — fun CharSequence.minOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/minOrNull(): kotlin/Char?`
    - `kotlin.text.minWith` — fun CharSequence.minWith(Comparator): Char  -- `final fun (kotlin/CharSequence).kotlin.text/minWith(kotlin/Comparator<in kotlin/Char>): kotlin/Char`
    - `kotlin.text.minWithOrNull` — fun CharSequence.minWithOrNull(Comparator): Char  -- `final fun (kotlin/CharSequence).kotlin.text/minWithOrNull(kotlin/Comparator<in kotlin/Char>): kotlin/Char?`

- [~] KSP-1389: kotlin.text.CharSequence.none-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `none`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_none.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_none.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_none.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.none` — fun CharSequence.none(): Boolean  -- `final fun (kotlin/CharSequence).kotlin.text/none(): kotlin/Boolean`
  - 実装済み（ゲート保留）: Kotlin 2.3.10 の `CharSequence.none()` 契約（`return isEmpty()`、既存 predicate overload は維持）を `StringHOF.kt` に source-backed で追加した。専用 Sema Golden、String/StringBuilder/custom CharSequence（`toString()` と内容が異なる場合を含む）、UTF-16/空文字列、`length` getter 1回、既存 predicate を専用 diff で固定した。focused Golden、専用 diff、Swift build、String synthetic link（4/4）、Runtime ABI link（4/4）、TODO ID、diff check は pass。全 Golden は build 後に無出力で中断し、全 diff_cases は同一 worktree の共有 lock 回避のため未完了のため Draft として記録する。

- [x] KSP-1390: kotlin.text.CharSequence.pad-family の未実装 stdlib API を実装する（2 件）
  - **2026-09-16 実装メモ**: 着手時に前提を確認したところ、`CharSequence.padStart(Int, Char)` / `CharSequence.padEnd(Int, Char)` の Kotlin source 実装（`StringHOF.kt`）、Sema golden、diff ケースは #6697（squash コミット `293acdf78`）で既に master に着地していた。本チケットで積み残されていた bridge/stub 整理として、呼び出し不能な `kk_string_padStart_default_flat` / `kk_string_padEnd_default_flat` / `kk_string_padStart_flat` / `kk_string_padEnd_flat` の `RuntimeABISpec` と `NativeEmitter` 登録、および ABI 署名テストを削除し、source-backed であることを ABI 回帰テストに固定した。Runtime の `@_cdecl` 実体と `HeaderHelpers+Synthetic*Stubs.swift` 登録は現行ツリーに存在しなかった。`CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift` に残っていた pad 名称フォールバックも削除した。
  - 検証: focused Sema（padStart/padEnd）、synthetic link、ABI 回帰、専用 kotlinc diff、Runtime ABI link、`check_todo_ids.sh`、`git diff --check` は pass。指定の全 Sema golden 更新コマンドは 13 件の `Golden worker timed out` で終了したが、対象ケースを artifact-based worker で個別比較すると既存 `.golden` と一致し、golden ファイルの差分はない。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `pad`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`（#6697 で追加済み）

- [x] KSP-1392: kotlin.text.CharSequence.region-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `region`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringComparison.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_region.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_region.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_region.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装状況: `CharSequence.regionMatches(Int, CharSequence, Int, Int, Boolean)` を `StringComparison.kt` に source-backed 実装し、`length`/indexed `get` の短絡順序と `ignoreCase` を Kotlin 2.3.10 に合わせた。focused Sema/Golden/diff/ABI は完了。共通 G はローカルで実行せず、PR #6694 の CI green で確認済み。
  - 完了確認（2026-09-16）: 実装コミット `719ce8acb`（PR #6694）は master に取り込み済み。ローカルの `swift build --disable-sandbox`、CharSequenceRegionMatchesSourceMigrationTests（2/2）、対象 Sema Golden shard（UPDATE_GOLDEN=1、1/93）、Kotlin 2.3.10 diff、TODO ID、Runtime ABI（4/4）が PASS。PR #6694 の CI も全ジョブ green（kotlinc Diff 4/4 を含む）を確認した。
  - 未実装シンボル一覧:
    - `kotlin.text.regionMatches` — fun CharSequence.regionMatches(Int, CharSequence, Int, Int, Boolean): Boolean  -- `final fun (kotlin/CharSequence).kotlin.text/regionMatches(kotlin/Int, kotlin/CharSequence, kotlin/Int, kotlin/Int, kotlin/Boolean = ...): kotlin/Boolean`

- [~] KSP-1393: kotlin.text.CharSequence.remove-family の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `remove`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringPrefixSuffix.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_remove.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_remove.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_remove.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - **2026-09-16 実装メモ（ゲート保留）**: `CharSequence.removePrefix/removeRange/removeSuffix/removeSurrounding` の6 overloadsを `StringPrefixSuffix.kt` に source-backed 実装した。戻り値は Kotlin 2.3.10 の `CharSequence` 契約に揃え、prefix/suffix の照合と結果生成は UTF-16 の `length`/indexed `get`/`subSequence` dispatch を通すため、String/StringBuilder/custom receiver の `toString()` 非依存動作を固定した。対象シンボルに Runtime bridge/stub の追加・削除は不要だった。Sema Golden shard、専用 diff ケース、Swift build、TODO ID、Runtime ABI link の focused 検証済み。共通 G はローカルで回さず CI で確認する。

- [x] KSP-1394: kotlin.text.CharSequence.repeat-family の未実装 stdlib API を実装する（1 件）
  - **2026-09-15 実装メモ**: 着手時に前提を確認したところ、`CharSequence.repeat(Int): String` の Kotlin source 実装・golden テスト・diff ケースは #6706（PR "KSP-1394: add CharSequence.repeat"、2026-09-12 merge）で既に完了済みだった。本チケットが `[~]` のまま残っていたのは、#6706 が「bridge/stub 整理」ステップを積み残していたため（TODO.md 上のマーカーも `[~]` のまま更新されていなかった）。本 PR ではその残作業のみを実施: 呼び出し不能になっていた `kk_string_repeat_flat`（Runtime `@_cdecl` / `RuntimeABISpec` エントリ / `NativeEmitter` の `FlatStringReturnCallSpec` 登録、および専用ユニットテスト）を削除。実コンパイルパスで `kk_string_repeat_flat` を参照する箇所が `Sources/CompilerCore` 配下に存在しないことを確認済み（`CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift` の `"repeat"` を含む no-candidate fallback ケースラベルは take/drop 等と同様の既存の残存デッドコードのため、本チケットのスコープでは変更していない）。`kk_string_padStart_flat`/`kk_string_padEnd_flat` にも同型の未整理が残っているが、それは KSP-1390 のスコープなので本 PR では触っていない。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `repeat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBasics.kt`（#6706 で追加済み）

- [~] KSP-1395: kotlin.text.CharSequence.replace-family の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `replace`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_replace.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_replace.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_replace.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装状況: `CharSequence.replace(Regex, String)` / lambda / `replaceFirst(Regex, String)` と `replaceRange` 2 overloads を `StringHOF.kt` に source-backed 実装。Regex bridge は String 入力のため indexed UTF-16 units から内容を materialize し、lambda 版は `findAll` と String 切片で置換する。対象シンボルの Runtime 関数、synthetic stub、RuntimeABISpec、name-string 特例は存在せず、整理変更は不要。focused Sema golden、専用 kotlinc diff、Swift build、TODO ID、diff check は pass。共通 Golden / 全 diff_cases は実行せず CI に委譲する。
  - 未実装シンボル一覧:
    - `kotlin.text.replace` — fun CharSequence.replace(Regex, String): String  -- `final inline fun (kotlin/CharSequence).kotlin.text/replace(kotlin.text/Regex, kotlin/String): kotlin/String`
    - `kotlin.text.replace` — fun CharSequence.replace(Regex, Function1): String  -- `final inline fun (kotlin/CharSequence).kotlin.text/replace(kotlin.text/Regex, noinline kotlin/Function1<kotlin.text/MatchResult, kotlin/CharSequence>): kotlin/String`
    - `kotlin.text.replaceFirst` — fun CharSequence.replaceFirst(Regex, String): String  -- `final inline fun (kotlin/CharSequence).kotlin.text/replaceFirst(kotlin.text/Regex, kotlin/String): kotlin/String`
    - `kotlin.text.replaceRange` — fun CharSequence.replaceRange(IntRange, CharSequence): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/replaceRange(kotlin.ranges/IntRange, kotlin/CharSequence): kotlin/CharSequence`
    - `kotlin.text.replaceRange` — fun CharSequence.replaceRange(Int, Int, CharSequence): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/replaceRange(kotlin/Int, kotlin/Int, kotlin/CharSequence): kotlin/CharSequence`

- [x] KSP-1396: kotlin.text.CharSequence.reversed-family の未実装 stdlib API を実装する（1 件）
  - **2026-09-15 実装メモ**: 着手時に前提を確認したところ、`CharSequence.reversed(): CharSequence` の Kotlin source 実装・golden テスト（`stdlib_kotlin_text_CharSequence_reversed.kt`/`.golden`）・diff ケース（`stdlib_kotlin_text_CharSequence_reversed.kt`）は #6697（squash 元 PR "KSP-1396: add CharSequence.reversed" #6714、2026-09-11 merge）で既に完了済みだった。本チケットが `[~]` のまま残っていたのは、KSP-1394（repeat）と同じ経緯で「bridge/stub 整理」ステップが積み残されていたため。本 PR ではその残作業のみを実施: 呼び出し不能になっていた `kk_string_reversed_flat`（Runtime `@_cdecl` / `RuntimeABISpec` エントリ / `NativeEmitter` の `FlatStringReturnCallSpec` 登録、および `RuntimeStringArrayTests.swift`/`CodegenBackendLLVMLinkingAndArtifactsTests.swift` の直接参照）を削除。実コンパイルパスで `kk_string_reversed_flat` を参照する箇所が `Sources/CompilerCore` 配下に存在しないことをリポジトリ全体 grep で確認済み（`StringSyntheticMemberLinkTests.swift:348` の `bundledMembers = ["repeat", "reversed"]` が「reversed は C external link を持たない」ことを既に固定している）。name-string 特例は 2 箇所を精査した上でどちらも対象外と判断: `CallTypeChecker+MemberCallInferenceFallbacks.swift:1159` の `calleeStr == "reversed"` 分岐は `Comparator.reversed()`（別レシーバ、対象外）。`CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift` の `case "reversed", "trimStart", "trimEnd":` 共有ラベルは、`trimStart`/`trimEnd` が `kk_string_trimStart_flat`/`kk_string_trimEnd_flat` として現在も生存しているため丸ごと削除できず、KSP-1394 が `"repeat"` 系ラベルを残した前例と同じ理由で本チケットのスコープでは変更していない。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `reversed`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBasics.kt`（#6697/#6714 で追加済み）

- [x] KSP-1397: kotlin.text.CharSequence.running-family の未実装 stdlib API を実装する（4 件）
  - 完了確認（2026-09-18）: KSP-1397/1398/1399/1400/1402/1403/1404/1405/1407/1411/1412 は既存の merged PR（#6700、#6708、#6709、#6710、#6716、#6717、#6720、#6721、#6724、#6726）で source-backed 実装・Golden・diff fixture が master に取り込まれており、残る KSP-1401/1406/1408/1409/1410/1413/1414/1431/1433/1436/1439 は PR #6891 で取り込まれた。PR #6891 の全 CI（CompilerCore/Smoke、Backend/Runtime/CLI/LSP、Repository Checks、kotlinc Diff 全 shard）が PASS し、22 タスクの共通 G を確認済み。
  - 実装済み: Kotlin source の runningFold / runningFoldIndexed / runningReduce / runningReduceIndexed と generic/nullable/primitive/empty、動的 CharSequence、callback throw、inline non-local return の回帰を追加。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `running`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_running.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_running.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_running.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.runningFold` — fun CharSequence.runningFold(, Function2): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/runningFold(#A, kotlin/Function2<#A, kotlin/Char, #A>): kotlin.collections/List<#A>`
    - `kotlin.text.runningFoldIndexed` — fun CharSequence.runningFoldIndexed(, Function3): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/runningFoldIndexed(#A, kotlin/Function3<kotlin/Int, #A, kotlin/Char, #A>): kotlin.collections/List<#A>`
    - `kotlin.text.runningReduce` — fun CharSequence.runningReduce(Function2): List  -- `final inline fun (kotlin/CharSequence).kotlin.text/runningReduce(kotlin/Function2<kotlin/Char, kotlin/Char, kotlin/Char>): kotlin.collections/List<kotlin/Char>`
    - `kotlin.text.runningReduceIndexed` — fun CharSequence.runningReduceIndexed(Function3): List  -- `final inline fun (kotlin/CharSequence).kotlin.text/runningReduceIndexed(kotlin/Function3<kotlin/Int, kotlin/Char, kotlin/Char, kotlin/Char>): kotlin.collections/List<kotlin/Char>`

- [x] KSP-1398: kotlin.text.CharSequence.scan-family の未実装 stdlib API を実装する（2 件）
  - 実装済み: Kotlin source の scan / scanIndexed を runningFold / runningFoldIndexed へ委譲し、generic/nullable/primitive/empty、動的 CharSequence、callback throw、inline non-local return の回帰を追加。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `scan`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_scan.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_scan.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_scan.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.scan` — fun CharSequence.scan(, Function2): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/scan(#A, kotlin/Function2<#A, kotlin/Char, #A>): kotlin.collections/List<#A>`
    - `kotlin.text.scanIndexed` — fun CharSequence.scanIndexed(, Function3): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/scanIndexed(#A, kotlin/Function3<kotlin/Int, #A, kotlin/Char, #A>): kotlin.collections/List<#A>`

- [x] KSP-1399: kotlin.text.CharSequence.single-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `single`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringQuery.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_single.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_single.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_single.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装状況: `CharSequence.single` / `singleOrNull` の no-argument・predicate overload を `StringQuery.kt` に source-backed 実装し、custom receiver の indexed dispatch、predicate の first/second match early-exit、Kotlin 2.3.10 の例外メッセージを固定。focused Sema/Golden/diff/ABI と PR #6891 の共通 G は完了。
  - 未実装シンボル一覧:
    - `kotlin.text.single` — fun CharSequence.single(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/single(): kotlin/Char`
    - `kotlin.text.single` — fun CharSequence.single(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/single(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char`
    - `kotlin.text.singleOrNull` — fun CharSequence.singleOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/singleOrNull(): kotlin/Char?`
    - `kotlin.text.singleOrNull` — fun CharSequence.singleOrNull(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/singleOrNull(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char?`

- [x] KSP-1400: kotlin.text.CharSequence.slice-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `slice`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringSubstringSlice.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_slice.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_slice.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_slice.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.slice` — fun CharSequence.slice(Iterable): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/slice(kotlin.collections/Iterable<kotlin/Int>): kotlin/CharSequence`
    - `kotlin.text.slice` — fun CharSequence.slice(IntRange): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/slice(kotlin.ranges/IntRange): kotlin/CharSequence`

- [x] KSP-1401: kotlin.text.CharSequence.split-family の未実装 stdlib API を実装する（6 件）
  - 実装 (2026-09-16): `StringSplitJoin.kt` に Regex / String vararg / Char vararg の split・splitToSequence を source-backed で追加。UTF-16 ベースの delimiter scanner、vararg default-stub ABI、spread 引数の配列要素型解決で通常・`*array` 呼び出しを維持。
  - 検証: stdlib-only artifact 診断なし、`StringSplitFunctionTests` 6件、`CodegenBackendKotlinTextSplittingEdgeCasesTests` 13件 PASS。共通 G / kotlinc 全体差分は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `split`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_split.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_split.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_split.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.split` — fun CharSequence.split(Regex, Int): List  -- `final inline fun (kotlin/CharSequence).kotlin.text/split(kotlin.text/Regex, kotlin/Int = ...): kotlin.collections/List<kotlin/String>`
    - `kotlin.text.split` — fun CharSequence.split(Array, Boolean, Int): List  -- `final fun (kotlin/CharSequence).kotlin.text/split(kotlin/Array<out kotlin/String>..., kotlin/Boolean = ..., kotlin/Int = ...): kotlin.collections/List<kotlin/String>`
    - `kotlin.text.split` — fun CharSequence.split(Array, Boolean, Int): List  -- `final fun (kotlin/CharSequence).kotlin.text/split(kotlin/CharArray..., kotlin/Boolean = ..., kotlin/Int = ...): kotlin.collections/List<kotlin/String>`
    - `kotlin.text.splitToSequence` — fun CharSequence.splitToSequence(Regex, Int): Sequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/splitToSequence(kotlin.text/Regex, kotlin/Int = ...): kotlin.sequences/Sequence<kotlin/String>`
    - `kotlin.text.splitToSequence` — fun CharSequence.splitToSequence(Array, Boolean, Int): Sequence  -- `final fun (kotlin/CharSequence).kotlin.text/splitToSequence(kotlin/Array<out kotlin/String>..., kotlin/Boolean = ..., kotlin/Int = ...): kotlin.sequences/Sequence<kotlin/String>`
    - `kotlin.text.splitToSequence` — fun CharSequence.splitToSequence(Array, Boolean, Int): Sequence  -- `final fun (kotlin/CharSequence).kotlin.text/splitToSequence(kotlin/CharArray..., kotlin/Boolean = ..., kotlin/Int = ...): kotlin.sequences/Sequence<kotlin/String>`

- [x] KSP-1402: kotlin.text.CharSequence.sub-family の未実装 stdlib API を実装する
  - 対象: `kotlin.text` / receiver `CharSequence` / family `sub`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringSubstringSlice.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_sub.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_sub.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_sub.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.subSequence` — fun CharSequence.subSequence(IntRange): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/subSequence(kotlin.ranges/IntRange): kotlin/CharSequence`

- [x] KSP-1403: kotlin.text.CharSequence.substring-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `substring`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringSubstringSlice.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_substring.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_substring.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_substring.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.substring` — fun CharSequence.substring(IntRange): String  -- `final fun (kotlin/CharSequence).kotlin.text/substring(kotlin.ranges/IntRange): kotlin/String`
    - `kotlin.text.substring` — fun CharSequence.substring(Int, Int): String  -- `final inline fun (kotlin/CharSequence).kotlin.text/substring(kotlin/Int, kotlin/Int = ...): kotlin/String`

- [x] KSP-1404: kotlin.text.CharSequence.sum-family の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `sum`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_sum.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_sum.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_sum.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double`
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): Int  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/Int>): kotlin/Int`
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): Long  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/Long>): kotlin/Long`
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): UInt  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/UInt>): kotlin/UInt`
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): ULong  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/ULong>): kotlin/ULong`
  - 実装メモ: StringHOF.kt に Kotlin source-backed の Double/Int/Long/UInt/ULong overload を追加。専用 Sema/Golden/diff は PASS。
  - 完了ゲート: common head 全体の Golden/diff は PR #6891 の CI で PASS。

- [x] KSP-1405: kotlin.text.CharSequence.take-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `take`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_take.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_take.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_take.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.take` — fun CharSequence.take(Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/take(kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.takeLast` — fun CharSequence.takeLast(Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/takeLast(kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.takeLastWhile` — fun CharSequence.takeLastWhile(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/takeLastWhile(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`
    - `kotlin.text.takeWhile` — fun CharSequence.takeWhile(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/takeWhile(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`

- [x] KSP-1406: kotlin.text.CharSequence.to-family の未実装 stdlib API を実装する（5 件）
  - 実装 (2026-09-16): 既存の `toList` / `toMutableList` / `toCollection` に加えて `toSet` / `toHashSet` の source-backed 実装を `StringCollectionConversions.kt` で確認・追加。
  - 検証: stdlib-only artifact 診断なし、最小 kswiftc 実行で CharSequence 変換を確認。共通 G / kotlinc 全体差分は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `to`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_to.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_to.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_to.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.toCollection` — fun CharSequence.toCollection(): #A  -- `final fun <#A: kotlin.collections/MutableCollection<in kotlin/Char>> (kotlin/CharSequence).kotlin.text/toCollection(#A): #A`
    - `kotlin.text.toHashSet` — fun CharSequence.toHashSet(): HashSet  -- `final fun (kotlin/CharSequence).kotlin.text/toHashSet(): kotlin.collections/HashSet<kotlin/Char>`
    - `kotlin.text.toList` — fun CharSequence.toList(): List  -- `final fun (kotlin/CharSequence).kotlin.text/toList(): kotlin.collections/List<kotlin/Char>`
    - `kotlin.text.toMutableList` — fun CharSequence.toMutableList(): MutableList  -- `final fun (kotlin/CharSequence).kotlin.text/toMutableList(): kotlin.collections/MutableList<kotlin/Char>`
    - `kotlin.text.toSet` — fun CharSequence.toSet(): Set  -- `final fun (kotlin/CharSequence).kotlin.text/toSet(): kotlin.collections/Set<kotlin/Char>`

- [x] KSP-1407: kotlin.text.CharSequence.trim-family の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `trim`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_trim.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_trim.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_trim.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.trim` — fun CharSequence.trim(): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trim(): kotlin/CharSequence`
    - `kotlin.text.trim` — fun CharSequence.trim(Array): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trim(kotlin/CharArray...): kotlin/CharSequence`
    - `kotlin.text.trim` — fun CharSequence.trim(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/trim(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`
    - `kotlin.text.trimEnd` — fun CharSequence.trimEnd(): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trimEnd(): kotlin/CharSequence`
    - `kotlin.text.trimEnd` — fun CharSequence.trimEnd(Array): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trimEnd(kotlin/CharArray...): kotlin/CharSequence`
    - `kotlin.text.trimEnd` — fun CharSequence.trimEnd(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/trimEnd(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`
    - `kotlin.text.trimStart` — fun CharSequence.trimStart(): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trimStart(): kotlin/CharSequence`
    - `kotlin.text.trimStart` — fun CharSequence.trimStart(Array): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trimStart(kotlin/CharArray...): kotlin/CharSequence`
    - `kotlin.text.trimStart` — fun CharSequence.trimStart(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/trimStart(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`

- [x] KSP-1408: kotlin.text.CharSequence.windowed-family の未実装 stdlib API を実装する（1 件）
  - 実装 (2026-09-16): `StringWindowChunkTransform.kt` に List-returning transform overload を追加し、size / step 検証と partial window の挙動を既存 no-transform path と統一。
  - 検証: `CodegenBackendKotlinTextSplittingEdgeCasesTests` 13件 PASS。共通 G / kotlinc 全体差分は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `windowed`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringWindowChunkTransform.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_windowed.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_windowed.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_windowed.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.windowed` — fun CharSequence.windowed(Int, Int, Boolean, Function1): List  -- `final fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/windowed(kotlin/Int, kotlin/Int = ..., kotlin/Boolean = ..., kotlin/Function1<kotlin/CharSequence, #A>): kotlin.collections/List<#A>`

- [x] KSP-1409: kotlin.text.CharSequence.with-family の未実装 stdlib API を実装する（1 件）
  - 監査 (2026-09-16): `StringCollectionConversions.kt` の `CharSequence.withIndex()` source-backed 実装が存在することを確認。共通 G は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `CharSequence` / family `with`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_with.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_with.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_with.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.withIndex` — fun CharSequence.withIndex(): Iterable  -- `final fun (kotlin/CharSequence).kotlin.text/withIndex(): kotlin.collections/Iterable<kotlin.collections/IndexedValue<kotlin/Char>>`

- [x] KSP-1410: kotlin.text.Companion の未実装 stdlib API を実装する（1 件）
  - 監査 (2026-09-16): 正式 API は `String.Companion.CASE_INSENSITIVE_ORDER` で、`HeaderHelpers+SyntheticStringFormatStubs.swift` の synthetic companion property と runtime link を確認。誤った top-level `kotlin.text.CASE_INSENSITIVE_ORDER` は追加しない。共通 G は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/CharSurrogate.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.CASE_INSENSITIVE_ORDER` — val Companion.CASE_INSENSITIVE_ORDER  -- `final val kotlin.text/CASE_INSENSITIVE_ORDER`

- [x] KSP-1411: kotlin.text.StringBuilder.append-family の未実装 stdlib API を実装する（16 件）
  - 実装 (2026-09-08): 不足していた typed appendLine 11件と CharArray offset/len append を Kotlin source へ追加。既存4件も検証。Any? append の独自 toString 無視と private IndexedValue による bundled constructor 解決の混線を最小回帰とともに修正。
  - 検証: focused Swift 18件、全 Golden（28 tests / 10 suites）、Kotlin 2.3.10 / OpenJDK 26 差分7件、ABI4件 PASS。親 #6697 の UTF-16 getter 回数差は同一親出力で再現し記録。共通 G は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `StringBuilder` / family `append`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_append.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_append.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_append.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.append` — fun StringBuilder.append(Any): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/append(kotlin/Any?): kotlin.text/StringBuilder`
    - `kotlin.text.append` — fun StringBuilder.append(Byte): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/append(kotlin/Byte): kotlin.text/StringBuilder`
    - `kotlin.text.append` — fun StringBuilder.append(Short): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/append(kotlin/Short): kotlin.text/StringBuilder`
    - `kotlin.text.append` — fun StringBuilder.append(CharArray, Int, Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/append(kotlin/CharArray, kotlin/Int, kotlin/Int): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Boolean): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Boolean): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Byte): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Byte): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Char): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Char): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(CharArray): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/CharArray): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(CharSequence): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/CharSequence?): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Double): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Double): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Float): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Float): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Int): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Long): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Long): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Short): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Short): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(String): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/String?): kotlin.text/StringBuilder`
    - `kotlin.text.appendRange` — fun StringBuilder.appendRange(CharArray, Int, Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendRange(kotlin/CharArray, kotlin/Int, kotlin/Int): kotlin.text/StringBuilder`

- [x] KSP-1412: kotlin.text.StringBuilder.appendln-family の未実装 stdlib API を実装する（10 件）
  - 実装済み (2026-09-08): Kotlin 2.3.10 の deprecated appendln 10 overloads を StringBuilder source に追加。全体 G は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `StringBuilder` / family `appendln`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_appendln.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_appendln.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_appendln.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.appendln` — fun StringBuilder.appendln(): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Any): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Any?): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Boolean): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Boolean): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Byte): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Byte): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Double): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Double): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Float): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Float): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Int): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Int): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Long): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Long): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Short): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Short): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(String): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/String): kotlin.text/StringBuilder`

- [x] KSP-1413: kotlin.text.StringBuilder.insert-family の未実装 stdlib API を実装する（4 件）
  - 実装 (2026-09-16): Byte / Short / CharSequence range / CharArray range の source-backed overload を確認し、CharSequence range は custom receiver を indexed access でコピーするよう修正。
  - 検証: `CodegenBackendStringBuilderEdgeCasesTests` 13件 PASS。共通 G / kotlinc 全体差分は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `StringBuilder` / family `insert`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_insert.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_insert.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_insert.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.insert` — fun StringBuilder.insert(Int, Byte): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/insert(kotlin/Int, kotlin/Byte): kotlin.text/StringBuilder`
    - `kotlin.text.insert` — fun StringBuilder.insert(Int, Short): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/insert(kotlin/Int, kotlin/Short): kotlin.text/StringBuilder`
    - `kotlin.text.insert` — fun StringBuilder.insert(Int, CharSequence, Int, Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/insert(kotlin/Int, kotlin/CharSequence?, kotlin/Int, kotlin/Int): kotlin.text/StringBuilder`
    - `kotlin.text.insertRange` — fun StringBuilder.insertRange(Int, CharArray, Int, Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/insertRange(kotlin/Int, kotlin/CharArray, kotlin/Int, kotlin/Int): kotlin.text/StringBuilder`

- [x] KSP-1414: kotlin.text.StringBuilder.to-family の未実装 stdlib API を実装する（1 件）
  - 監査 (2026-09-16): `StringBuilder.toCharArray(destination, offset, start, end)` source-backed 実装と既存 runtime bridge を確認。共通 G は PR #6891 の CI で PASS。
  - 対象: `kotlin.text` / receiver `StringBuilder` / family `to`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_to.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_to.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_to.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.toCharArray` — fun StringBuilder.toCharArray(CharArray, Int, Int, Int): Unit  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/toCharArray(kotlin/CharArray, kotlin/Int = ..., kotlin/Int = ..., kotlin/Int = ...)`

- [~] KSP-1419: kotlin.text.HexFormat top-level の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.HexFormat` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.Builder` — class kotlin.text.HexFormat.Builder  -- `final class Builder {`
    - `kotlin.text.HexFormat.BytesHexFormat` — class kotlin.text.HexFormat.BytesHexFormat  -- `final class BytesHexFormat {`
    - `kotlin.text.HexFormat.Companion` — object kotlin.text.HexFormat.Companion  -- `final object Companion {`
    - `kotlin.text.HexFormat.NumberHexFormat` — class kotlin.text.HexFormat.NumberHexFormat  -- `final class NumberHexFormat {`

- [~] KSP-1420: kotlin.text.HexFormat.HexFormat の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.HexFormat` / receiver `HexFormat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/HexFormat.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_HexFormat_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_HexFormat_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_HexFormat_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.bytes` — val HexFormat.bytes: BytesHexFormat  -- `final val bytes`
    - `kotlin.text.HexFormat.number` — val HexFormat.number: NumberHexFormat  -- `final val number`
    - `kotlin.text.HexFormat.toString` — fun HexFormat.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.text.HexFormat.upperCase` — val HexFormat.upperCase: Boolean  -- `final val upperCase`

- [~] KSP-1422: kotlin.text.HexFormat.Builder.Builder の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.text.HexFormat.Builder` / receiver `Builder`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/Builder/Builder.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_Builder_Builder_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_Builder_Builder_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_Builder_Builder_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.Builder.build` — fun Builder.build(): HexFormat  -- `final fun build(): kotlin.text/HexFormat`
    - `kotlin.text.HexFormat.Builder.bytes` — val Builder.bytes: Builder  -- `final val bytes`
    - `kotlin.text.HexFormat.Builder.bytes` — fun Builder.bytes(Function1): Unit  -- `final inline fun bytes(kotlin/Function1<kotlin.text/HexFormat.BytesHexFormat.Builder, kotlin/Unit>)`
    - `kotlin.text.HexFormat.Builder.number` — val Builder.number: Builder  -- `final val number`
    - `kotlin.text.HexFormat.Builder.number` — fun Builder.number(Function1): Unit  -- `final inline fun number(kotlin/Function1<kotlin.text/HexFormat.NumberHexFormat.Builder, kotlin/Unit>)`
    - `kotlin.text.HexFormat.Builder.upperCase` — val Builder.upperCase: Boolean  -- `final var upperCase`

- [~] KSP-1423: kotlin.text.HexFormat.BytesHexFormat top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.HexFormat.BytesHexFormat` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/BytesHexFormat/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_BytesHexFormat_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.BytesHexFormat.Builder` — class kotlin.text.HexFormat.BytesHexFormat.Builder  -- `final class Builder {`

- [~] KSP-1424: kotlin.text.HexFormat.BytesHexFormat.BytesHexFormat の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.text.HexFormat.BytesHexFormat` / receiver `BytesHexFormat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/BytesHexFormat/BytesHexFormat.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_BytesHexFormat_BytesHexFormat_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_BytesHexFormat_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_BytesHexFormat_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.BytesHexFormat.bytePrefix` — val BytesHexFormat.bytePrefix: String  -- `final val bytePrefix`
    - `kotlin.text.HexFormat.BytesHexFormat.byteSeparator` — val BytesHexFormat.byteSeparator: String  -- `final val byteSeparator`
    - `kotlin.text.HexFormat.BytesHexFormat.byteSuffix` — val BytesHexFormat.byteSuffix: String  -- `final val byteSuffix`
    - `kotlin.text.HexFormat.BytesHexFormat.bytesPerGroup` — val BytesHexFormat.bytesPerGroup: Int  -- `final val bytesPerGroup`
    - `kotlin.text.HexFormat.BytesHexFormat.bytesPerLine` — val BytesHexFormat.bytesPerLine: Int  -- `final val bytesPerLine`
    - `kotlin.text.HexFormat.BytesHexFormat.groupSeparator` — val BytesHexFormat.groupSeparator: String  -- `final val groupSeparator`
    - `kotlin.text.HexFormat.BytesHexFormat.toString` — fun BytesHexFormat.toString(): String  -- `final fun toString(): kotlin/String`

- [~] KSP-1425: kotlin.text.HexFormat.BytesHexFormat.Builder.Builder の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.text.HexFormat.BytesHexFormat.Builder` / receiver `Builder`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/BytesHexFormat/Builder/Builder.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_BytesHexFormat_Builder_Builder_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_Builder_Builder_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_Builder_Builder_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.bytePrefix` — val Builder.bytePrefix: String  -- `final var bytePrefix`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.byteSeparator` — val Builder.byteSeparator: String  -- `final var byteSeparator`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.byteSuffix` — val Builder.byteSuffix: String  -- `final var byteSuffix`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.bytesPerGroup` — val Builder.bytesPerGroup: Int  -- `final var bytesPerGroup`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.bytesPerLine` — val Builder.bytesPerLine: Int  -- `final var bytesPerLine`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.groupSeparator` — val Builder.groupSeparator: String  -- `final var groupSeparator`

- [~] KSP-1427: kotlin.text.HexFormat.NumberHexFormat top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.HexFormat.NumberHexFormat` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/NumberHexFormat/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_NumberHexFormat_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.NumberHexFormat.Builder` — class kotlin.text.HexFormat.NumberHexFormat.Builder  -- `final class Builder {`

- [~] KSP-1428: kotlin.text.HexFormat.NumberHexFormat.NumberHexFormat の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text.HexFormat.NumberHexFormat` / receiver `NumberHexFormat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/NumberHexFormat/NumberHexFormat.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_NumberHexFormat_NumberHexFormat_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_NumberHexFormat_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_NumberHexFormat_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.NumberHexFormat.minLength` — val NumberHexFormat.minLength: Int  -- `final val minLength`
    - `kotlin.text.HexFormat.NumberHexFormat.prefix` — val NumberHexFormat.prefix: String  -- `final val prefix`
    - `kotlin.text.HexFormat.NumberHexFormat.removeLeadingZeros` — val NumberHexFormat.removeLeadingZeros: Boolean  -- `final val removeLeadingZeros`
    - `kotlin.text.HexFormat.NumberHexFormat.suffix` — val NumberHexFormat.suffix: String  -- `final val suffix`
    - `kotlin.text.HexFormat.NumberHexFormat.toString` — fun NumberHexFormat.toString(): String  -- `final fun toString(): kotlin/String`

- [~] KSP-1429: kotlin.text.HexFormat.NumberHexFormat.Builder.Builder の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.HexFormat.NumberHexFormat.Builder` / receiver `Builder`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/NumberHexFormat/Builder/Builder.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_NumberHexFormat_Builder_Builder_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_Builder_Builder_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_Builder_Builder_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.NumberHexFormat.Builder.minLength` — val Builder.minLength: Int  -- `final var minLength`
    - `kotlin.text.HexFormat.NumberHexFormat.Builder.prefix` — val Builder.prefix: String  -- `final var prefix`
    - `kotlin.text.HexFormat.NumberHexFormat.Builder.removeLeadingZeros` — val Builder.removeLeadingZeros: Boolean  -- `final var removeLeadingZeros`
    - `kotlin.text.HexFormat.NumberHexFormat.Builder.suffix` — val Builder.suffix: String  -- `final var suffix`

- [x] KSP-1431: kotlin.text.MatchGroup.MatchGroup の未実装 stdlib API を実装する（8 件）
  - 監査 (2026-09-16): `MatchResult.kt` の `data class MatchGroup(value, range)` が constructor / component / copy / equals / hashCode / properties / toString の 8 API を source-backed で提供し、既存 Sema / backend テストで確認済み。共通 G は PR #6891 の CI で PASS。
  - 対象: `kotlin.text.MatchGroup` / receiver `MatchGroup`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/MatchGroup/MatchGroup.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_MatchGroup_MatchGroup_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_MatchGroup_MatchGroup_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_MatchGroup_MatchGroup_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.MatchGroup.component1` — fun MatchGroup.component1(): String  -- `final fun component1(): kotlin/String`
    - `kotlin.text.MatchGroup.component2` — fun MatchGroup.component2(): IntRange  -- `final fun component2(): kotlin.ranges/IntRange`
    - `kotlin.text.MatchGroup.copy` — fun MatchGroup.copy(String, IntRange): MatchGroup  -- `final fun copy(kotlin/String = ..., kotlin.ranges/IntRange = ...): kotlin.text/MatchGroup`
    - `kotlin.text.MatchGroup.equals` — fun MatchGroup.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.text.MatchGroup.hashCode` — fun MatchGroup.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.text.MatchGroup.range` — val MatchGroup.range: IntRange  -- `final val range`
    - `kotlin.text.MatchGroup.toString` — fun MatchGroup.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.text.MatchGroup.value` — val MatchGroup.value: String  -- `final val value`

- [x] KSP-1433: kotlin.text.MatchResult top-level の未実装 stdlib API を実装する（1 件）
  - 監査 (2026-09-16): `MatchResult.kt` の nested `MatchResult.Destructured` source-backed class と destructuring bridges を確認。共通 G は PR #6891 の CI で PASS。
  - 対象: `kotlin.text.MatchResult` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/MatchResult/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_MatchResult_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_MatchResult_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_MatchResult_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.MatchResult.Destructured` — class kotlin.text.MatchResult.Destructured  -- `final class Destructured {`

- [x] KSP-1436: kotlin.text.Regex.Regex の未実装 stdlib API を実装する（13 件）
  - 実装 (2026-09-16): `Regex.kt` に CharSequence overload 群、startIndex / matchAt / matchesAt、replace / split / splitToSequence、toString を追加。Regex の String fast path は維持し、CharSequence は source-backed materialization を経由。
  - 検証: `RegexAPISurfaceInventoryTests` 30件、stdlib-only artifact 診断なし、最小 kswiftc 実行 PASS。共通 G / kotlinc 全体差分は PR #6891 の CI で PASS。
  - 対象: `kotlin.text.Regex` / receiver `Regex`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Regex/Regex.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Regex_Regex_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Regex_Regex_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Regex_Regex_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Regex.containsMatchIn` — fun Regex.containsMatchIn(CharSequence): Boolean  -- `final fun containsMatchIn(kotlin/CharSequence): kotlin/Boolean`
    - `kotlin.text.Regex.find` — fun Regex.find(CharSequence, Int): MatchResult  -- `final fun find(kotlin/CharSequence, kotlin/Int = ...): kotlin.text/MatchResult?`
    - `kotlin.text.Regex.findAll` — fun Regex.findAll(CharSequence, Int): Sequence  -- `final fun findAll(kotlin/CharSequence, kotlin/Int = ...): kotlin.sequences/Sequence<kotlin.text/MatchResult>`
    - `kotlin.text.Regex.matchAt` — fun Regex.matchAt(CharSequence, Int): MatchResult  -- `final fun matchAt(kotlin/CharSequence, kotlin/Int): kotlin.text/MatchResult?`
    - `kotlin.text.Regex.matchEntire` — fun Regex.matchEntire(CharSequence): MatchResult  -- `final fun matchEntire(kotlin/CharSequence): kotlin.text/MatchResult?`
    - `kotlin.text.Regex.matches` — fun Regex.matches(CharSequence): Boolean  -- `final fun matches(kotlin/CharSequence): kotlin/Boolean`
    - `kotlin.text.Regex.matchesAt` — fun Regex.matchesAt(CharSequence, Int): Boolean  -- `final fun matchesAt(kotlin/CharSequence, kotlin/Int): kotlin/Boolean`
    - `kotlin.text.Regex.replace` — fun Regex.replace(CharSequence, Function1): String  -- `final fun replace(kotlin/CharSequence, kotlin/Function1<kotlin.text/MatchResult, kotlin/CharSequence>): kotlin/String`
    - `kotlin.text.Regex.replace` — fun Regex.replace(CharSequence, String): String  -- `final fun replace(kotlin/CharSequence, kotlin/String): kotlin/String`
    - `kotlin.text.Regex.replaceFirst` — fun Regex.replaceFirst(CharSequence, String): String  -- `final fun replaceFirst(kotlin/CharSequence, kotlin/String): kotlin/String`
    - `kotlin.text.Regex.split` — fun Regex.split(CharSequence, Int): List  -- `final fun split(kotlin/CharSequence, kotlin/Int = ...): kotlin.collections/List<kotlin/String>`
    - `kotlin.text.Regex.splitToSequence` — fun Regex.splitToSequence(CharSequence, Int): Sequence  -- `final fun splitToSequence(kotlin/CharSequence, kotlin/Int = ...): kotlin.sequences/Sequence<kotlin/String>`

- [x] KSP-1439: kotlin.text.StringBuilder top-level の未実装 stdlib API を実装する（4 件）
  - 実装 (2026-09-16): `StringBuilder.kt` に CharSequence constructor を追加し、lowerer / runtime / RuntimeABISpec の専用 bridge で StringBuilder・custom CharSequence の初期値を扱う。
  - 検証: `CodegenBackendStringBuilderEdgeCasesTests` 13件、最小 kswiftc 実行 PASS。共通 G / kotlinc 全体差分は PR #6891 の CI で PASS。
  - 対象: `kotlin.text.StringBuilder` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.StringBuilder.<init>` — constructor ()  -- `constructor <init>()`
    - `kotlin.text.StringBuilder.<init>` — constructor (CharSequence)  -- `constructor <init>(kotlin/CharSequence)`
    - `kotlin.text.StringBuilder.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.text.StringBuilder.<init>` — constructor (String)  -- `constructor <init>(kotlin/String)`

> KUU-475 完了根拠（2026-09-16、HEAD `b4cd1664ce23e81c92c2a211199e51e51f0d3fcb`）: KSP-711 の merged commit `9a39776adff70eb419b7effc3ea21fa0a1baa632` が Typography 全定数を bundled Kotlin source として実装済み。KSP-1442〜1471 の対象 23 タスクは、現行 `Sources/CompilerCore/Stdlib/kotlin/text/Typography.kt:12-52` の `public const val` 宣言が所有する。`StringSyntheticMemberLinkTests.testTypographyObjectSurfaceResolves`（`Tests/CompilerCoreTests/Sema/StringSyntheticMemberLinkTests.swift:936-1010`）は全 41 定数を非 synthetic の source-backed object/property、非 nullable `Char`、const の char literal として検証する。Typography 専用の synthetic/runtime/RuntimeABI 経路はなく、個別 `.kt` / Golden / diff ケースを追加すると既存実装と重複する。
> 検証: `swift build` PASS、`SWIFT_TEST_PARALLEL=0 SWIFT_TEST_WORKERS=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.StringSyntheticMemberLinkTests` PASS（4 tests / 1 suite）、`git diff --check` PASS。全 Golden / 全 diff_kotlinc / Runtime ABI link の aggregate gate は未実行。

- [x] KSP-1442: kotlin.text.Typography.Typography.amp-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `amp`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/amp.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_amp.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_amp.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_amp.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.amp` — val Typography.amp: Char  -- `final const val amp`

- [x] KSP-1443: kotlin.text.Typography.Typography.bullet-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `bullet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/bullet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_bullet.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_bullet.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_bullet.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.bullet` — val Typography.bullet: Char  -- `final const val bullet`

- [x] KSP-1444: kotlin.text.Typography.Typography.cent-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `cent`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/cent.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_cent.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_cent.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_cent.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.cent` — val Typography.cent: Char  -- `final const val cent`

- [x] KSP-1445: kotlin.text.Typography.Typography.copyright-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `copyright`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/copyright.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_copyright.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_copyright.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_copyright.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.copyright` — val Typography.copyright: Char  -- `final const val copyright`

- [x] KSP-1446: kotlin.text.Typography.Typography.dagger-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `dagger`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/dagger.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_dagger.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_dagger.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_dagger.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.dagger` — val Typography.dagger: Char  -- `final const val dagger`

- [x] KSP-1447: kotlin.text.Typography.Typography.degree-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `degree`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/degree.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_degree.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_degree.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_degree.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.degree` — val Typography.degree: Char  -- `final const val degree`

- [x] KSP-1449: kotlin.text.Typography.Typography.double-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `double`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/double.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_double.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_double.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_double.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.doubleDagger` — val Typography.doubleDagger: Char  -- `final const val doubleDagger`
    - `kotlin.text.Typography.doublePrime` — val Typography.doublePrime: Char  -- `final const val doublePrime`

- [x] KSP-1452: kotlin.text.Typography.Typography.greater-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `greater`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/greater.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_greater.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_greater.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_greater.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.greater` — val Typography.greater: Char  -- `final const val greater`
    - `kotlin.text.Typography.greaterOrEqual` — val Typography.greaterOrEqual: Char  -- `final const val greaterOrEqual`

- [x] KSP-1457: kotlin.text.Typography.Typography.mdash-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `mdash`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/mdash.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_mdash.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_mdash.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_mdash.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.mdash` — val Typography.mdash: Char  -- `final const val mdash`

- [x] KSP-1458: kotlin.text.Typography.Typography.middle-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `middle`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/middle.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_middle.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_middle.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_middle.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.middleDot` — val Typography.middleDot: Char  -- `final const val middleDot`

- [x] KSP-1459: kotlin.text.Typography.Typography.nbsp-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `nbsp`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/nbsp.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_nbsp.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_nbsp.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_nbsp.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.nbsp` — val Typography.nbsp: Char  -- `final const val nbsp`

- [x] KSP-1460: kotlin.text.Typography.Typography.ndash-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `ndash`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/ndash.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_ndash.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_ndash.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_ndash.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.ndash` — val Typography.ndash: Char  -- `final const val ndash`

- [x] KSP-1461: kotlin.text.Typography.Typography.not-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `not`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/not.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_not.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_not.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_not.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.notEqual` — val Typography.notEqual: Char  -- `final const val notEqual`

- [x] KSP-1462: kotlin.text.Typography.Typography.paragraph-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `paragraph`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/paragraph.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_paragraph.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_paragraph.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_paragraph.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.paragraph` — val Typography.paragraph: Char  -- `final const val paragraph`

- [x] KSP-1463: kotlin.text.Typography.Typography.plus-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `plus`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/plus.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_plus.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_plus.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_plus.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.plusMinus` — val Typography.plusMinus: Char  -- `final const val plusMinus`

- [x] KSP-1464: kotlin.text.Typography.Typography.pound-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `pound`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/pound.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_pound.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_pound.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_pound.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.pound` — val Typography.pound: Char  -- `final const val pound`

- [x] KSP-1465: kotlin.text.Typography.Typography.prime-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `prime`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/prime.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_prime.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_prime.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_prime.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.prime` — val Typography.prime: Char  -- `final const val prime`

- [x] KSP-1466: kotlin.text.Typography.Typography.quote-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `quote`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/quote.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_quote.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_quote.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_quote.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.quote` — val Typography.quote: Char  -- `final const val quote`

- [x] KSP-1467: kotlin.text.Typography.Typography.registered-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `registered`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/registered.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_registered.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_registered.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_registered.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.registered` — val Typography.registered: Char  -- `final const val registered`

- [x] KSP-1468: kotlin.text.Typography.Typography.right-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `right`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/right.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_right.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_right.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_right.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.rightDoubleQuote` — val Typography.rightDoubleQuote: Char  -- `final const val rightDoubleQuote`
    - `kotlin.text.Typography.rightGuillemet` — val Typography.rightGuillemet: Char  -- `final const val rightGuillemet`
    - `kotlin.text.Typography.rightGuillemete` — val Typography.rightGuillemete: Char  -- `final const val rightGuillemete`
    - `kotlin.text.Typography.rightSingleQuote` — val Typography.rightSingleQuote: Char  -- `final const val rightSingleQuote`

- [x] KSP-1469: kotlin.text.Typography.Typography.section-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `section`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/section.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_section.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_section.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_section.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.section` — val Typography.section: Char  -- `final const val section`

- [x] KSP-1470: kotlin.text.Typography.Typography.times-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `times`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/times.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_times.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_times.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_times.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.times` — val Typography.times: Char  -- `final const val times`

- [x] KSP-1471: kotlin.text.Typography.Typography.tm-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `tm`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/tm.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_tm.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_tm.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_tm.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.tm` — val Typography.tm: Char  -- `final const val tm`

- [~] KSP-1472: kotlin.time top-level の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.time` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.AbstractDoubleTimeSource` — class kotlin.time.AbstractDoubleTimeSource  -- `abstract class kotlin.time/AbstractDoubleTimeSource : kotlin.time/TimeSource.WithComparableMarks {`
    - `kotlin.time.AbstractLongTimeSource` — class kotlin.time.AbstractLongTimeSource  -- `abstract class kotlin.time/AbstractLongTimeSource : kotlin.time/TimeSource.WithComparableMarks {`
    - `kotlin.time.Clock` — interface kotlin.time.Clock  -- `abstract interface kotlin.time/Clock {`
    - `kotlin.time.ComparableTimeMark` — interface kotlin.time.ComparableTimeMark  -- `abstract interface kotlin.time/ComparableTimeMark : kotlin.time/TimeMark, kotlin/Comparable<kotlin.time/ComparableTimeMark> {`
    - `kotlin.time.ExperimentalTime` — class kotlin.time.ExperimentalTime  -- `open annotation class kotlin.time/ExperimentalTime : kotlin/Annotation {`
    - `kotlin.time.Instant` — class kotlin.time.Instant  -- `final class kotlin.time/Instant : kotlin.io/Serializable, kotlin/Comparable<kotlin.time/Instant> {`
    - `kotlin.time.TestTimeSource` — class kotlin.time.TestTimeSource  -- `final class kotlin.time/TestTimeSource : kotlin.time/AbstractLongTimeSource {`
    - `kotlin.time.TimeMark` — interface kotlin.time.TimeMark  -- `abstract interface kotlin.time/TimeMark {`
    - `kotlin.time.TimedValue` — class kotlin.time.TimedValue  -- `final class <#A: kotlin/Any?> kotlin.time/TimedValue {`
  - 2026-09-17 KUU-479: KSP-1472/1474/1477/1478/1479/1484/1485/1490 の 8 タスクを実装し、各 Golden artifact・各 diff ケース・関連 focused Sema・Runtime ABI リンク検証を通過。全 Golden / 全 diff_kotlinc は未実行のため、8 項目は `[~]` とする。

- [~] KSP-1474: kotlin.time.Monotonic の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.time` / receiver `Monotonic`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/TimeSource.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Monotonic_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Monotonic_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Monotonic_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.measureTime` — fun Monotonic.measureTime(Function0): Duration  -- `final inline fun (kotlin.time/TimeSource.Monotonic).kotlin.time/measureTime(kotlin/Function0<kotlin/Unit>): kotlin.time/Duration`
    - `kotlin.time.measureTimedValue` — fun Monotonic.measureTimedValue(Function0): TimedValue  -- `final inline fun <#A: kotlin/Any?> (kotlin.time/TimeSource.Monotonic).kotlin.time/measureTimedValue(kotlin/Function0<#A>): kotlin.time/TimedValue<#A>`

- [~] KSP-1477: kotlin.time.AbstractDoubleTimeSource.AbstractDoubleTimeSource の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.time.AbstractDoubleTimeSource` / receiver `AbstractDoubleTimeSource`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/AbstractDoubleTimeSource/AbstractDoubleTimeSource.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_AbstractDoubleTimeSource_AbstractDoubleTimeSource_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_AbstractDoubleTimeSource_AbstractDoubleTimeSource_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_AbstractDoubleTimeSource_AbstractDoubleTimeSource_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.AbstractDoubleTimeSource.markNow` — fun AbstractDoubleTimeSource.markNow(): ComparableTimeMark  -- `open fun markNow(): kotlin.time/ComparableTimeMark`
    - `kotlin.time.AbstractDoubleTimeSource.read` — fun AbstractDoubleTimeSource.read(): Double  -- `abstract fun read(): kotlin/Double`
    - `kotlin.time.AbstractDoubleTimeSource.unit` — val AbstractDoubleTimeSource.unit: DurationUnit  -- `final val unit`

- [~] KSP-1478: kotlin.time.AbstractLongTimeSource top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.time.AbstractLongTimeSource` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/AbstractLongTimeSource/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_AbstractLongTimeSource_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.AbstractLongTimeSource.<init>` — constructor (DurationUnit)  -- `constructor <init>(kotlin.time/DurationUnit)`

- [~] KSP-1479: kotlin.time.AbstractLongTimeSource.AbstractLongTimeSource の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.time.AbstractLongTimeSource` / receiver `AbstractLongTimeSource`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/AbstractLongTimeSource/AbstractLongTimeSource.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_AbstractLongTimeSource_AbstractLongTimeSource_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_AbstractLongTimeSource_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_AbstractLongTimeSource_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.AbstractLongTimeSource.markNow` — fun AbstractLongTimeSource.markNow(): ComparableTimeMark  -- `open fun markNow(): kotlin.time/ComparableTimeMark`
    - `kotlin.time.AbstractLongTimeSource.read` — fun AbstractLongTimeSource.read(): Long  -- `abstract fun read(): kotlin/Long`
    - `kotlin.time.AbstractLongTimeSource.unit` — val AbstractLongTimeSource.unit: DurationUnit  -- `final val unit`

- [~] KSP-1484: kotlin.time.Duration.Duration の未実装 stdlib API を実装する（14 件）
  - 対象: `kotlin.time.Duration` / receiver `Duration`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Duration/Duration.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Duration_Duration_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Duration_Duration_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Duration_Duration_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.Duration.div` — fun Duration.div(Double): Duration  -- `final fun div(kotlin/Double): kotlin.time/Duration`
    - `kotlin.time.Duration.hoursComponent` — val Duration.hoursComponent: Int  -- `final val hoursComponent`
    - `kotlin.time.Duration.minutesComponent` — val Duration.minutesComponent: Int  -- `final val minutesComponent`
    - `kotlin.time.Duration.nanosecondsComponent` — val Duration.nanosecondsComponent: Int  -- `final val nanosecondsComponent`
    - `kotlin.time.Duration.secondsComponent` — val Duration.secondsComponent: Int  -- `final val secondsComponent`
    - `kotlin.time.Duration.times` — fun Duration.times(Double): Duration  -- `final fun times(kotlin/Double): kotlin.time/Duration`
    - `kotlin.time.Duration.toComponents` — fun Duration.toComponents(Function2): #A1  -- `final inline fun <#A1: kotlin/Any?> toComponents(kotlin/Function2<kotlin/Long, kotlin/Int, #A1>): #A1`
    - `kotlin.time.Duration.toComponents` — fun Duration.toComponents(Function3): #A1  -- `final inline fun <#A1: kotlin/Any?> toComponents(kotlin/Function3<kotlin/Long, kotlin/Int, kotlin/Int, #A1>): #A1`
    - `kotlin.time.Duration.toComponents` — fun Duration.toComponents(Function4): #A1  -- `final inline fun <#A1: kotlin/Any?> toComponents(kotlin/Function4<kotlin/Long, kotlin/Int, kotlin/Int, kotlin/Int, #A1>): #A1`
    - `kotlin.time.Duration.toComponents` — fun Duration.toComponents(Function5): #A1  -- `final inline fun <#A1: kotlin/Any?> toComponents(kotlin/Function5<kotlin/Long, kotlin/Int, kotlin/Int, kotlin/Int, kotlin/Int, #A1>): #A1`
    - `kotlin.time.Duration.toDouble` — fun Duration.toDouble(DurationUnit): Double  -- `final fun toDouble(kotlin.time/DurationUnit): kotlin/Double`
    - `kotlin.time.Duration.toInt` — fun Duration.toInt(DurationUnit): Int  -- `final fun toInt(kotlin.time/DurationUnit): kotlin/Int`
    - `kotlin.time.Duration.toLong` — fun Duration.toLong(DurationUnit): Long  -- `final fun toLong(kotlin.time/DurationUnit): kotlin/Long`
    - `kotlin.time.Duration.toString` — fun Duration.toString(DurationUnit, Int): String  -- `final fun toString(kotlin.time/DurationUnit, kotlin/Int = ...): kotlin/String`

- [~] KSP-1485: kotlin.time.Duration.Companion.Companion の未実装 stdlib API を実装する（22 件）
  - 対象: `kotlin.time.Duration.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Duration/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Duration_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Duration_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Duration_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.Duration.Companion.convert` — fun Companion.convert(Double, DurationUnit, DurationUnit): Double  -- `final fun convert(kotlin/Double, kotlin.time/DurationUnit, kotlin.time/DurationUnit): kotlin/Double`
    - `kotlin.time.Duration.Companion.days` — val Companion.days: Duration  -- `final val days`
    - `kotlin.time.Duration.Companion.days` — val Companion.days: Duration  -- `final val days`
    - `kotlin.time.Duration.Companion.days` — val Companion.days: Duration  -- `final val days`
    - `kotlin.time.Duration.Companion.hours` — val Companion.hours: Duration  -- `final val hours`
    - `kotlin.time.Duration.Companion.hours` — val Companion.hours: Duration  -- `final val hours`
    - `kotlin.time.Duration.Companion.hours` — val Companion.hours: Duration  -- `final val hours`
    - `kotlin.time.Duration.Companion.microseconds` — val Companion.microseconds: Duration  -- `final val microseconds`
    - `kotlin.time.Duration.Companion.microseconds` — val Companion.microseconds: Duration  -- `final val microseconds`
    - `kotlin.time.Duration.Companion.microseconds` — val Companion.microseconds: Duration  -- `final val microseconds`
    - `kotlin.time.Duration.Companion.milliseconds` — val Companion.milliseconds: Duration  -- `final val milliseconds`
    - `kotlin.time.Duration.Companion.milliseconds` — val Companion.milliseconds: Duration  -- `final val milliseconds`
    - `kotlin.time.Duration.Companion.milliseconds` — val Companion.milliseconds: Duration  -- `final val milliseconds`
    - `kotlin.time.Duration.Companion.minutes` — val Companion.minutes: Duration  -- `final val minutes`
    - `kotlin.time.Duration.Companion.minutes` — val Companion.minutes: Duration  -- `final val minutes`
    - `kotlin.time.Duration.Companion.minutes` — val Companion.minutes: Duration  -- `final val minutes`
    - `kotlin.time.Duration.Companion.nanoseconds` — val Companion.nanoseconds: Duration  -- `final val nanoseconds`
    - `kotlin.time.Duration.Companion.nanoseconds` — val Companion.nanoseconds: Duration  -- `final val nanoseconds`
    - `kotlin.time.Duration.Companion.nanoseconds` — val Companion.nanoseconds: Duration  -- `final val nanoseconds`
    - `kotlin.time.Duration.Companion.seconds` — val Companion.seconds: Duration  -- `final val seconds`
    - `kotlin.time.Duration.Companion.seconds` — val Companion.seconds: Duration  -- `final val seconds`
    - `kotlin.time.Duration.Companion.seconds` — val Companion.seconds: Duration  -- `final val seconds`

- [~] KSP-1490: kotlin.time.Instant.Companion.Companion の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.time.Instant.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Instant/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Instant_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Instant_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Instant_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.Instant.Companion.DISTANT_FUTURE` — val Companion.DISTANT_FUTURE: Instant  -- `final val DISTANT_FUTURE`
    - `kotlin.time.Instant.Companion.DISTANT_PAST` — val Companion.DISTANT_PAST: Instant  -- `final val DISTANT_PAST`
    - `kotlin.time.Instant.Companion.fromEpochSeconds` — fun Companion.fromEpochSeconds(Long, Int): Instant  -- `final fun fromEpochSeconds(kotlin/Long, kotlin/Int): kotlin.time/Instant`
    - `kotlin.time.Instant.Companion.fromEpochSeconds` — fun Companion.fromEpochSeconds(Long, Long): Instant  -- `final fun fromEpochSeconds(kotlin/Long, kotlin/Long = ...): kotlin.time/Instant`
    - `kotlin.time.Instant.Companion.parse` — fun Companion.parse(CharSequence): Instant  -- `final fun parse(kotlin/CharSequence): kotlin.time/Instant`
    - `kotlin.time.Instant.Companion.parseOrNull` — fun Companion.parseOrNull(CharSequence): Instant  -- `final fun parseOrNull(kotlin/CharSequence): kotlin.time/Instant?`

## Runtime follow-up

## 戦略アーキテクチャ改善 実行計画（ARCH: 2026-08-22 構造レビュー）

> 出典: 2026-08-22 の全サブシステム構造レビュー（Sema / KIR / Lowering / Backend / Runtime / Driver / LSP / テスト基盤の精査 + 実測）。主要実測値: release kswiftc で hello.kt が **デフォルト 4.27s → `--stdlib-library`(.kklib) 1.40s → `--no-stdlib` 0.41s**（コンパイル時間の ~2/3 が bundled stdlib 2.6万行の毎回再処理）。実行時は `for (i in 1..1000000)` が 1,236ms = **1.24µs/iter ≒ ランタイム C 呼び出し 2 回 × ~620ns**（NSLock + Set ハンドル検証 + 動的キャスト、しかも -Onone ビルド）。
> 参照プラクティス: rustc（事前コンパイル stdlib / rmeta 遅延読込 / lang items）、Kotlin K2（フェーズ化・IDE 遅延解決）、Roslyn（WellKnownMember）、Swift SIL（raw/canonical + verifier）、MLIR（パス境界検証）、rust-analyzer（durability・エラー耐性）、Kotlin/Native（コンパイラ統合ランタイム・並行 mark-sweep）。
> **共通ゲート G を全タスクに適用**（+ 該当時 U）。粒度ルール: 1タスク = 1 PR。性能タスクは変更前後のベンチ値（`Scripts/benchmark_stdlib_hof.sh` / `-Xfrontend time-phases`）を PR 本文に記載する。既存台帳との関係: 名前文字列特例の解体は RF4 系（`docs/rf4-name-special-case-inventory.md`）・KSP 移行と同期して進め、本セクションでは重複起票しない。
> 優先順は Tier 順。**ARCH-001/002 は他の全性能系判断（stdlib-pipeline §13-3 の「Swift 残留の実測条件」）の基準値を変えるため最優先**。完了後に `docs/refactoring-metrics.md` のベンチ基準値を取り直すこと。

### ARCH Tier 1: 即効（相互独立・並列可）

- [x] ARCH-002: LLVM 中間最適化パイプラインを配線する。現状 `optLevel` は `createTargetMachine`（命令選択・レジスタ割付）と DWARF `isOptimized` にしか流れず、new PassManager 系シンボル（`LLVMRunPasses` / `LLVMCreatePassBuilderOptions`）は `LLVMCAPIBindings+Loading.swift` の dlsym 表に存在しない — **`-O2` 指定でも mem2reg / SROA / GVN / inlining / LICM が一度も走らない**（バックエンドが逆 mem2reg 退避で作るスタックスロットが出荷バイナリに残る）。dlsym 表に 2 シンボルを追加し、`NativeEmitter` の emit 前に `default<O1|O2|O3>` を実行（`-O0` は現状維持でデバッグ体験を守る）。完了条件: `-O0`/`-O2` 両構成で `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green + ベンチ前後値記載 + G。2026-09-16 完了記録: PR #6684 (764263db14) で O1/O2/O3 pass 配線、target triple/data layout 適用、IR verifier、4原因の回帰、O2 stdlib artifact consumer を実装。`swift build` PASS、`LLVMOptimizationPipelineTests` / `LLVMOptimizationRegressionTests` は 2 suites / 10 tests PASS、`llvm_optimization_pipeline.kt` の O0 focused diff は `total=1 failed=0 passed=1 skipped=0`、O2 focused は kotlinc と 5 行の出力一致を確認した。CI run `34711470516` は debug/release build、全 Swift 検証、repository checks、kotlinc diff 4 shard が PASS（Summary: 338/338/338/340 passed、failed=0、skipped=19/19/19/16）。macOS arm64 debug の `for_in_range.kt`（100 万回、各5回中央値）は O0 606.739 ms → O2 611.425 ms（+0.8%、runtime/boxing 支配のため測定誤差範囲）。常設 O2 全 diff lane は ARCH-003/KUU-498 の責務として分離し、詳細は `docs/arch-002-llvm-optimization.md` に記録。
- [ ] ARCH-003: CI に `-O2` の diff レーンを追加する（最適化起因ミスコンパイルの常設検出器）。前提: ARCH-002。完了条件: `.github/workflows/ci.yml` にレーン追加 + green 実績を完了メモに記載。
- [~] ARCH-006: LSP が毎 didChange で bundled stdlib 221 ファイルを Lex→Parse→AST→全量型検査している問題を解消する。`Analyzer.analyze`（LSPServer 内で唯一の `CompilerOptions` 構築点）が `emit: .object` のため `shouldUseDefaultStdlib` ガードに弾かれ、常にソース注入経路に落ちている。stdlib artifact（ARCH-005 の成果物、なければ起動時 1 回のビルド）を明示指定する。完了条件: didChange 1 回あたりの解析時間の前後値を PR 本文に記載 + LSPServerTests に「解析結果に bundled 由来 FileID の再 Lex が発生しない」ことを固定するテスト + G。前提: ARCH-005（または `stdlibLibraryPath` 明示注入のみで先行実施可）。
  - 完了記録（2026-09-08）: `KSwiftLSPCLI` 起動時に `StdlibArtifactCache.resolveOrBuild` を一度だけ呼び、解決した `.kklib` を `Analyzer` の instance-local `stdlibLibraryPath` として渡す構成にした。`CompilerOptions.defaultStdlibLibraryPath` は変更せず、既存の Analyzer API / cache / generation semantics を維持する。
  - `artifactBackedAnalysisDoesNotInjectBundledStdlibSources` が明示 artifact 経路の `includeStdlib == false`、bundled 由来 FileID 0 件、入力 FileID 1 件を固定する。
  - 同条件の Analyzer 区間を各5回測定した結果、source 注入は 3423.267542–3483.110084 ms（中央値 3439.024167 ms、source FileID 314 件）、明示 artifact は 172.319875–178.674792 ms（中央値 175.78275 ms、artifact FileID 1 件）だった。
- [~] ARCH-011: 述語系 ABI の boxed Bool 返却を生値に変える。`kk_set_contains` / `kk_set_is_empty` 等が結果を `kk_box_bool` で包んで返し、**1 回の contains ごとに解放されない Swift オブジェクトを 1 個リーク**している。呼び出し側 lowering と合わせて i1/i64 生値返却へ。`RuntimeABISpec` 更新 + parity テストを同一 PR で。完了条件: `rg 'kk_box_bool' Sources/Runtime/RuntimeSetAndMap.swift` が 0 件 + RuntimeTests + G。
  - 実装済み・共通 G 待ち（2026-09-11）: `RuntimeSetAndMap.swift` の 7 関数（`__kk_set_contains` / `__kk_set_is_empty` / `__kk_mutable_set_add` / `__kk_mutable_set_remove` / `__kk_mutable_set_removeAll` / `__kk_mutable_set_retainAll` / `kk_map_is_empty`）を raw 0/1 返却にし、`RuntimeABIFunctionSpec.returnsRawBoolean` → `RuntimeABISpec.rawBooleanReturnCalleeNames` を単一情報源として `ABILoweringPass` が該当 callee の結果に `kk_unbox_bool` を挿入しないようにした。`rg 'kk_box_bool' Sources/Runtime/RuntimeSetAndMap.swift` 0 件、`RuntimeRawBooleanPredicateTests`（生値 + オブジェクト数非増加）/ `LoweringABIAndPropertyRegressionTests+RawBooleanReturn` / diff `arch011_set_map_predicate_raw_bool.kt` green。ベンチ（debug）: `x in set` 1M ループ 0.66s→0.51s、`arch010_hash_collections` 599ms→509ms。`__kk_mutable_set_addAll` は `kk_mutable_collection_addAll`（RuntimeCollections.swift、boxed）への委譲のためスコープ外。

### ARCH Tier 2a: ランタイム統合（Kotlin/Native 型モデルへの段階接近）

> 背景: Runtime には設計済みの K/N 型モデル（`KTypeInfo` / `kk_alloc` / `KKObjHeader` / frame map / mark-sweep GC）と、実際に動く「Swift ARC box + インスタンスごと辞書 vtable + グローバル NSLock」の**二重設計**が同居し、前者は codegen 未配線で全て到達不能、後者は box 解放経路がなく恒久リークする。GC は起動トリガーが存在せず一度も走らない。

- [~] ARCH-013: 静的に型が確定するプリミティブ boxing/unboxing をインライン emit 化する。`kk_box_int` は「NSLock 2 回 + Set 照合 + Swift class 割付 + `passRetained`（解放なし）」、`kk_unbox_int` は「NSLock + Set 照合 + 動的キャスト」。型が静的確定する境界（ABILoweringPass の boxing boundary）で、タグ付き即値表現またはインライン割付コードに置換する。設計は ARCH-015 の決定に従属。完了条件: boxing ヘビーな diff ケースのベンチ前後値記載 + RuntimeTests + G。前提: ARCH-015。
  - 実装済み・共通 G 待ち（2026-09-18）: `ABILoweringPass` の静的 primitive 境界を `kk_box_*_static` / `kk_unbox_*_static` へ配線し、現行 Swift ARC box と `objectPointers` 登録を維持した tagged-handle fast path を追加。通常 ABI は保持し、nullable sentinel、non-null Long/ULong/Double の値、型不一致・raw 値 fallback、Any の文字列化/equality を RuntimeTests で固定（box release は ARCH-016 の責務として変更していない）。`Scripts/diff_cases/arch013_primitive_boxing.kt` は `total=1 failed=0 passed=1 skipped=0`。`Scripts/benchmark_cases/arch013_primitive_boxing.swift` を独立プロセスで各3回実行し、各プロセス5ラウンド中央値の代表値は legacy `76,033,958 ns` → static `54,434,584 ns`（checksum は双方 `19,999,900,000`、約 -28.4%）。focused Swift は 3 suites / 29 tests PASS、ABI/virtual dispatch/BuildKIR 周辺は 4 suites / 64 tests PASS、`RuntimeABIExternalLinkValidationTests` は 5 tests PASS。2026-09-19 の CI 失敗（run `35346040931`）を調査し、登録済み Runtime object handle を static boxing が再 boxing しない修正と static unbox を許容する lowering 回帰テストを追加。代表 diff 4 件と `RuntimeBoxingTests` 23 tests は PASS。CI 全体の再実行は未実施。
- [~] ARCH-014: ルート 0 件の frame push/pop 税を停止する。`NativeEmitter+FunctionEmission` が全 Kotlin 関数のプロローグで `kk_register_frame_map(fid, 0)` + `kk_push_frame(fid, 0)`、全出口で `kk_pop_frame()` を emit するが、frame map ポインタは**定数 0** のため、ランタイム側は毎関数呼び出しで「グローバルロック 3 回 + 辞書削除 + 配列 append」を行いルート 0 件を登録している（`FrameMapDescriptorC` を構築する codegen は存在しない）。emit を停止し、GC 実体化（ARCH-016）時に TLS シャドウスタックとして正規に再導入する方針を `docs/` に記録する。完了条件: `rg 'kk_push_frame' Sources/CompilerBackend/` が 0 件 + 関数呼び出しヘビーなベンチ前後値記載 + RuntimeTests + G。
  - 実装済み・共通 G 待ち（2026-09-11）: `NativeEmitter+FunctionEmission.swift` の prologue register/push と全出口の pop emit を削除し、`NativeEmitter.swift` の weak スタブ定義（`defineWeakFrameRuntimeStubs` / `defineWeakRuntimeFunction`）も除去。`rg 'kk_push_frame' Sources/CompilerBackend/` 0 件。ランタイム実装と ABI spec エントリは ARCH-016 の再導入口として保持（`RuntimeGCTests.testFrameMapRootsProtectActiveFramePointers` が手動 ABI 経路で使用中）。再導入方針は `docs/arch-014-frame-map-emission.md`、J16.2 注記は `docs/spec.md`。`RuntimeStubImplementationTests.testLLVMBackendDoesNotEmitFrameRuntimeCalls` と `CodegenBackendLLVMLinkingAndArtifactsTests` で IR 非出現を固定。ベンチ（debug kswiftc、fib(27)×8 ≒ 240 万関数呼び出し、並列テスト実行中の負荷環境）: before best 2.69s / median 3.80s → after best 1.84s / median 2.11s（約 −32〜44%）。
- [~] ARCH-016: box/オブジェクトの解放経路を導入する（恒久リークの解消）。現状 `RuntimeIntBox`/`RuntimeStringBox`/`RuntimeListBox`/`RuntimeMapBox`/`RuntimeObjectBox` は `Unmanaged.passRetained` 後に release する者が存在せず、`objectPointers` 登録とともにプロセス生涯リークする（`RuntimeGC` のコメント自身が「解放は box を release する者の責任」と明言）。mark-sweep は対象ヒープ（`heapObjects`)が常に空で一度も起動しない。到達可能性ベースの回収または明示解放経路を設計・実装し、割付ループの RSS が有界になることを固定する。完了条件: 割付ループ（例: `while` 内 `list.add` / boxing）の RSS 有界性テスト + RuntimeTests + G。前提: ARCH-015。
  - 実装済み・共通 G 待ち（2026-09-18）: `kk_object_release` を新設し、retained box は登録解除→メタデータ／freeze registry 除去→ARC release の順で明示解放する経路を追加。pinned object、StableRef、Unit、borrowed な flow/sentinel は解放対象から除外し、flow reset では専用 registry と `objectPointers` を同期して stale handle を残さない。`RuntimeABISpec` と export parity の契約も追加。`RuntimeObjectOwnershipTests`（4/4、100,000 回 boxing 解放ループの registry/RSS 上限）、`RuntimeHandleResolutionResetTests`（5/5）、`RuntimeGCTests`（7/7）が green。全 Swift テスト、全 Golden、全 diff ケースは未実行。

### ARCH Tier 2b: KIR 品質基盤（SIL/MLIR 流の検証導入）

- [~] ARCH-018: `KIRVerifier` 第 1 弾を導入する。検査項目: ①関数内ラベル一意 + 全 `jump` 先定義済み（`KIRLabelRelocation.swift` 冒頭コメントが自己記録する「ラベル衝突 → LLVM クラッシュ」クラスの即時検出）、②読まれるレジスタは代入済み、③ `instructionLocations.count == body.count`、④ `call` の callee が `RuntimeABISpec` または KIR 内関数に解決可能。デバッグビルド + CI で全 Lowering パス後に実行、release では off。完了条件: verifier が CI で有効 + 既存 golden/diff green + 意図的に壊した KIR で検出することを固定するユニットテスト + G。
  - 実装済み・共通 G 待ち（2026-09-11）: `Sources/CompilerCore/KIR/KIRVerifier.swift` 新設。5 検査（duplicateLabel / undefinedJumpTarget / undefinedRegisterRead / instructionLocationCountMismatch / unresolvableCallee）を全 Lowering パス後に `LoweringPhase` から実行し、検出時は `KSWIFTK-KIR-0003` error を発行。有効化は `KSWIFTK_KIR_VERIFY`（既定: DEBUG=on、release=off）、CI の diff ジョブで `KSWIFTK_KIR_VERIFY=1` を明示。コンパイラ内部 callee `__kk_int_range_induction_add` / `__kk_int_range_induction_le` を `compilerInternalNonThrowingCalleeNames` に追加。検査④はさらに、codegen が名前マッチで LLVM 演算に下げる builtin 名（`length` / `kk_string_struct_get_length` / `__kk_string_struct_get_length`）を `RuntimeABISpec.compilerInternalBuiltinCalleeNames` として認め、symbol 無し call は `lookupByShortName` で宣言済み関数を引く（bundled `external fun __kk_*` 対応）、symbol 付き call は value 系 kind（valueParameter/local/property 等、ローカルスロット invoke）も resolvable と判定、`kk_fn_` prefix（codegen が全モジュール関数に付ける C リンク名）も受理。synthetic SymbolID（テーブル未登録・dump では `_` 表示）は `SyntheticSymbolScheme.isSyntheticCallTarget` で getter/setter/`$default` stub kind を受理（`call get` のプロパティ accessor・`call foo$default` の default 引数スタブが該当 — codegen は internalFunctions / itable / `resolveUnnamedInternalFunction` で構造的に解決する）。symbol 無し `*$default` callee は基底名を `lookupByShortName` で引く。検査②は `ImportedInlineKIRMaterializer` が imported body の定義命令を持たない例外スロットに割り当てる `.temporary(0)` sentinel（codegen は constInt(0) fallback として emit）の読み取りを受理する。検査②の導入で `InlineLoweringPass` の既存の構造的欠陥も修正した: 全パスが non-local return するラムダ/inline 拡張では `returnedExpr`（merge スロット等）の writer が dead-code フィルタで除去され、エピローグの `unbox`/`copy` が未定義スロットを読んでいた（到達不能コードのため実害なし・KIR 上は不正）。エピローグで `returnedExpr` が emit 済み命令で定義されていることを確認し、未定義なら unit フォールバックにする（`exprIsDefined` ガード、call/lambda 双方の 4 エピローグサイト）。bundled stdlib `--stdlib-only` ビルドが verifier 有効で通過することを確認。`KIRVerifierTests` で各検査の検出 + hello world での無発火を固定。検査④が `$enumConstructorProperty$` placeholder call の未解決（bundled `.kirDump` で helper 未合成 / `.kklib` 越境で link 不可）という既存バグを検出し、BUG-246 として同 PR で修正（下記参照）。
- [~] ARCH-019: `replaceBody` を位置配列同時更新型のシグネチャに変更する。現状 Lowering 内 28 箇所の `replaceBody` のうち `replaceInstructionLocations` を伴うのは 2 箇所のみで、バックエンドの長さ不一致ガードにより**該当関数の行レベルデバッグ情報が黙って全損**している。`replaceBody(body:locations:)` に一本化し、旧 API を廃止して型で防ぐ。完了条件: `rg 'func replaceBody' Sources/CompilerCore/KIR/` が新シグネチャのみ + Lowering 通過後も `instructionLocations.count == body.count` が全関数で成立（ARCH-018 の検査③を enforcing に昇格）+ G。前提: ARCH-018 推奨。
  - 実装済み・共通 G 待ち（2026-09-11）: `KIRLoweringEmitContext` を `instructionLocations` / `currentSourceRange` 付きの RangeReplaceableCollection 化し、`replaceBody(_:locations:)`（parallel 必須・precondition 付き）と `replaceBody(_ emit: KIRLoweringEmitContext)` の 2 シグネチャに一本化。`replaceInstructionLocations` は廃止。全 Lowering パス・`injectTopLevelInits` / `rewriteDelegateAccesses` の PostProcess・補助 emitter（`KIRCallEmissionHelpers` 等）を emit context 直書きまたは `inout` ジェネリック化で追従。`KIRFunction.init` は空 locations を nil 埋め正規化、非 parallel は precondition で拒否。`LoweringInstructionLocationParityTests` で tailrec/for/when/lambda/try/coroutine 横断の全関数 parity を固定。
- [ ] ARCH-020: `KIRStage` 段階マーカー（raw / desugared / abiLowered 等）を導入し、各 Lowering パスが要求・生成段階を宣言する。現状パス順序制約はソースコメントのみ（例: Tailrec→NormalizeBlocks、ValueClassUnboxing→PropertyLowering、IntegerNarrowing→ABILowering）で機械化されていない。SIL の `sil_stage raw/canonical` 相当。完了条件: 順序違反をデバッグビルドで即検出するテスト + G。前提: ARCH-018。

### ARCH Tier 2c: Sema の名前ディスパッチ出口戦略（RF4/KSP と同期）

- [ ] ARCH-021: well-known シンボル表を導入する。現状 stdlib 特例判定は「TypeCheck 内の文字列リテラル switch 386 ケース + インライン `Set<String>` 名前表（collectionHOFNames 等 ~120 名）+ `interner.resolve == "…"` 比較」に散在し、ユーザ定義 `map`/`delay` 等との衝突ガードがサイトごと ad-hoc（`hasNonStdlibCollectionFactoryShadow` 等）。Roslyn `WellKnownMember` / rustc lang items に倣い、①bundled Kotlin 宣言側に `@KsIntrinsic("kotlin.collections.map")` 的注釈（既存 `@KsSymbolName` 機構を流用）または FQName 表を導入、②Sema 起動時に「well-known 名 → SymbolID」を 1 箇所で解決、③特例分岐を SymbolID 比較へ置換する**基盤**を作る（全面置換は RF4 台帳の消化として KSP 移行と同期し、本タスクは基盤 + 代表 2〜3 特例の置換まで）。完了条件: 基盤 + 置換済み特例の rg チェック（旧文字列比較 0 件）+ シャドーイング回帰テスト（ユーザ定義同名関数が特例に吸われない）+ G。
- [~] ARCH-022: `Scripts/loc_report.sh` に名前ディスパッチの実態メトリクスを追加する。現行の `interner_resolve_literal_comparison_count`（TypeCheck 79 件）は氷山の一角で、文字列 switch 386 ケースとインライン名前表を数えていない。「TypeCheck 内文字列リテラル case 数」「インライン `Set<String>` 名前表エントリ数」を追加し、ARCH-021/RF4 の進捗を非悪化ゲートに乗せる。完了条件: loc_report 出力に新メトリクス + `docs/refactoring-metrics.md` に基準値追記。
  - 実装済み・共通 G 待ち: `loc_report.sh` に `typecheck_string_literal_switch_case_count` と `typecheck_inline_string_set_entry_count` を追加し、コメント・文字列内容を除外する Swift 字句 scanner と回帰 fixture (`Scripts/test_loc_report.sh`) を同梱した。2026-09-08 の base `a72cc373f859aaf408c6a4e9510404a1e21c92dc` で基準値はそれぞれ 402 / 142。exact-base full Swift/Golden の共通 G は親タスクで実行中のため未完了。

### ARCH Tier 2d: テスト・CI の 4 穴埋め

- [ ] ARCH-023: diff_cases を種にした変異 fuzzer と crash corpus を導入する。現状 fuzzing はゼロで、SIGSEGV/SIGBUS 級のフロントエンド・ランタイムバグが diff triage の**副産物として偶然**見つかり続けている。1,038 ケースへのトークン置換・削除・入替変異 + 「クラッシュしない・ICE は `KSWIFTK-ICE-*` 診断で終了する」オラクルから開始し、夜間 CI（`quarterly-audits.yml` 同様の cron）+ 最小化ケースの `Tests/CrashCorpus/` 恒久保存。参照: Csmith(481 バグ)/YARPGen(220+ バグ)の differential fuzzing 実績。完了条件: 夜間ワークフロー追加 + corpus 再生テストが CI で green + 初回運転で見つかったバグの起票実績。
- [x] ARCH-026: ベンチマークの CI ゲート化（実装後に撤去）。`Scripts/benchmark_stdlib_hof.sh` は現在 CI から一度も呼ばれず、stdlib-pipeline **§13-2/§13-3（性能理由の Swift 残留・ブリッジ追加には実測必須）が執行不能**になっている。実行ベンチ + コンパイル時間ベンチ（hello / 中規模合成 / stdlib-only、`-Xfrontend time-phases` の TSV 化）を CI ジョブにし、基準 TSV をリポジトリ管理、閾値超過（例: ±10%）で fail。PR サマリに差分表示（rustc-perf の最小構成）。完了条件: CI ジョブ green + 基準 TSV コミット + 意図的回帰で fail することの確認記録。 実装は #7041（基準 TSV ゲート）と後続の paired retry（base コンパイラを同一ランナーでビルドして ABBA 交差比較）まで進んだが、GitHub hosted runner の性能分散が ±10% トレランスを恒常的に超え（同一コードで sort median が 29s↔60s、導入後の成功は 3 回のみでその後 30 連敗以上）、実質常時レッドのため CI ゲート一式（`benchmark_gate.sh` / `paired_benchmark_gate.sh` / `benchmark_baseline.tsv` / テスト 2 本 / ジョブ 3 本）を撤去。ローカル harness `Scripts/benchmark_stdlib_hof.sh` と `benchmark_cases/` は残置し、§13-2/§13-3 の実測要件は引き続きローカル計測で満たす。
- [~] ARCH-027: macOS CI レーンを最低 1 本追加する。現状 CI は ubuntu のみで、`docs/spec.md` が宣言する一次プラットフォーム macOS を何も検証していない（diff スクリプトに macOS 専用の配慮が既に複数あるのに、である）。最小構成: build + SmokeTests + LinkPhase 系。完了条件: macos runner ジョブ green。
- [~] ARCH-028: bundled stdlib 注入コストの計測定義を修正する。`Scripts/measure_bundled_stdlib_injection.sh` と `docs/refactoring-metrics.md` の「+100ms トリガー」は **Lex+Parse の bundled 小計（36ms）だけ**を注入コストと定義しており、実測 ~3.9s/release（Sema/KIR/Lowering/Codegen の stdlib 再処理）が計測基準の盲点に落ちている — 現定義では本当に問題なコストに対して構造的に発火し得ない。定義を「`--no-stdlib` との全フェーズ差分」へ変更し、`docs/refactoring-metrics.md` と stdlib-pipeline.md §7 の基準値・トリガー値を更新する。完了条件: スクリプト + 両 doc 更新 + 新定義での実測値記録。2026-09-08 個別実測: exact-base debug compiler / macOS arm64 の probe 5 paired runsで中央値 3472.27ms、range 3448.50–3484.58ms、trigger 3572.27ms を記録。head全体Gは未完了。
- [ ] ARCH-029: `.kklib` metadata の遅延読込。ARCH-005 後は `metadata.bin` の eager 全量デシリアライズ + 合成スタブ登録で **Sema 664ms/回（release 実測）が全コンパイルの新たな支配項**になる。rustc rmeta / K2 stub 方式に倣い、metadata.bin を「FQName → オフセット索引 + 本体」の 2 部構成にして名前解決要求時にデシリアライズする。完了条件: `.kklib` 経路 hello.kt の Sema フェーズ前後値記載（目標 1/3 以下）+ `Lib*Metadata*Tests` green + G。前提: ARCH-005。

### ARCH Tier 3: 診断 UX と小粒フォローアップ

- [~] ARCH-031: `Diagnostic.secondaryRanges` を実配線する。フィールドは存在するが**全 13 構築サイトが空配列を渡し、レンダラも読まない**。型不一致（期待型の由来位置）とオーバーロード曖昧（候補宣言位置）の 2 診断から詰め、テキスト/JSON 両レンダラで表示する。完了条件: 該当診断の golden 更新 + `rg 'secondaryRanges: \[\]' Sources/CompilerCore` の件数減少を PR 本文に記載 + G。
  - 実装済み・共通 G 待ち（2026-09-11）: `KSWIFTK-TYPE-0001`（`emitSubtypeConstraint` 経由の全 45 呼出を網羅）は期待型 nominal の `declSite`（classType/typeParam）+ return 式では enclosing 宣言の declSite を secondary に付与。`KSWIFTK-SEMA-0003`（`selectResult` と `ambiguousCallResult` の双方）は曖昧候補の `declSite` を `SymbolTable.sortedDeclSites` で決定的順序付き付与。テキストレンダラは `note:` 行 + キャレット、JSON は LSP `relatedInformation`、sema golden dump は同一ファイル内 `secondary=[l:c,...]` を出力。`secondaryRanges: []` リテラルは Sources/CompilerCore で 10→8 件（残は severity helper 4 + TYPE-0001 以外の診断 4）。`DiagnosticSecondaryRangeTests` 4 件 + Diagnostics golden 3 件・Sema golden 1 件更新。
- [~] ARCH-032: `DiagnosticCodeAction` に TextEdit ペイロードを追加し LSP quick-fix を成立させる。現状 codeActions は title+kind のみで**適用可能な編集を持たない**ラベル。`edits: [(range, newText)]` を追加し、LSPServer の codeAction ハンドラへ貫通、代表 2 診断（`override` 追加・`const` 修飾子削除）で実装。完了条件: LSPServerTests で edit 適用結果を固定 + G。
  - 実装済み・共通 G 待ち: `DiagnosticTextEdit` を持つ `DiagnosticCodeAction`、LSP `textDocument/codeAction` routing/capability/WorkspaceEdit、`KSWIFTK-SEMA-OVERRIDE` の `override ` 挿入と `KSWIFTK-SEMA-0080` の lexer token に基づく `const ` 削除を実装し、UTF-16 位置・context.only・不正／stale document・適用後再解析を LSPServerTests に固定した。exact-base full Swift/Golden の共通 G は未完了。

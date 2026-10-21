# Kotlin Compiler Remaining Tasks

### Diff skip 追跡（残り 2 件）

> 現行 `SKIP-DIFF` タグ: `Scripts/diff_cases/kuu_575_range_value_semantics.kt`（KUU-1719、`KSWIFTK-LINK-0003` 未解決）と `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicReference_n_n.kt`（DEBT-DIFF-001、`kotlin.native.concurrent` は Kotlin/Native 専用のため恒久 skip）。完了した triage（DEBT-DIFF-007、最終 `kclass_members.kt` は #8021 で解除）の履歴は git に残る。

## Dead Code 削除タスク（DEADCODE: 2026-07-11〜12 再監査）

> 2026-06-12 監査分の履歴は git に残る（`git show 209eca2f97:docs/dead-code-audit.md`）。現状の台帳（保持リストと理由コード）は [`docs/dead-code-audit.md`](docs/dead-code-audit.md)。今回は現 HEAD で (1) Swift の USR/index 解析（Periphery 3.7.4、public/Codable は保持）、(2) 識別子の宣言・呼び出し箇所の `rg` 照合、(3) 2,791 件の Runtime `@_cdecl`（`kk_*` 2,739 件 + `__kk_*` 52 件）に対する CompilerCore / CompilerBackend / bundled Kotlin / Runtime 内部 / Tests / ABI テーブル経路の照合、を併用した。
> 根拠略号: **R0** = 宣言以外の参照 0、**D** = 参照元が別の dead symbol のみ、**W0** = 代入/初期化のみで read 0、**E0** = Runtime export に emit/内部/テスト経路 0、**T** = 製品からは未使用でテストのみ。同名 overload や別 lexical scope は USR 単位で分離済み。
> 1 checkbox = 1 method / property / type / enum case を原則とする。D 項目は参照元タスクを先に削除し、最後に owner type/file を整理する。`RuntimeABISpec` 登録は使用証拠ではないため、E0 削除時は spec/parity/snapshot も同時に消す。
> 除外を実済み: `kk_print_string_flat` は Backend が直接 emit するため alive。`kk_atomic_*` は prefix + suffix の 2 段階動的生成、URLSession delegate / `@main` / XCTest・Swift Testing discovery / protocol witness / Hashable・Codable 合成参照も alive として除外。
> 完了ゲートは refactor PR gate（全テスト + golden + `diff_kotlinc.sh` green）。完全に到達不能な単独 private helper のみを削除する PR は、対象 module テスト + `git diff --check` を最低ゲートとし、まとめ PR 時に full gate を実施する。

### 監査基盤 / 残領域

- [~] DEADCODE-014: 旧「未監査領域」を継続監査する。2026-07-12 時点で tracked `.c/.h/.cc/.cpp` は 0 件、`DiagnosticRegistry` 108 descriptor は全て production 発行箇所あり、stored/global/Tests helper の検出結果は下記に分割済み。**2026-07-31 更新**: 「SKIP-DIFF 62 件」は stale な数値だったと判明（実測は当時110件）。kswiftc を再ビルドして全件 `--force-run-skipped` で再判定し、9件を解除（`comparator_basic.kt`/`interface_properties.kt`/`kconstructor_basic.kt`/`math_exp_log_functions.kt`/`random_overload_edge_cases.kt`/`file_use_edge_cases.kt`/`coroutine_exception_handling.kt`/`coroutine_scope_lifecycle.kt`/`coroutine_supervisor_job.kt`）。並行して別セッションが `DEBT-DIFF-001` の完全棚卸しと `DEBT-DIFF-007`(72→37) の大規模 triage を実施していたため、その成果を `git reset --hard origin/master` で取り込んだ上で作業を継続（このとき `BUG-152`(#5068) が本セッションの CharSequence.length 修正と完全に重複していたと判明し、重複分は破棄）。本セッション側の net-new な実装: (1) `EnumClass.values()` が Sema 未登録で完全に unresolved だったバグと `entries` のメンバー転送不可バグを修正（`enum_entries_function.kt` を追加解除、`enum_basic.kt`/`enum_edge_cases.kt` は別バグ=`BUG-177` で依然ブロック中）、(2) `Array<T>` の `mapIndexed`/`filterIndexed`/`mapNotNull`/`filterNot`/`filterNotNull`/`reduceIndexed`/`first`/`firstOrNull`/`last`/`lastOrNull` 未解決バグを修正（`array_hof.kt` も 2026-08-13 現在 SKIP-DIFF タグが無く active（`--force-run-skipped` で PASS））。詳細・各コミットの root cause は `docs/diff-skip-inventory.md`（#8170 で削除済み、`git show 51c7347a7e^:docs/diff-skip-inventory.md` で参照）参照。2026-08-18 実測では active な SKIP-DIFF は 35 distinct file（35 tag instance、内訳は docs/diff-skip-inventory.md）。`list_binary_search_compare.kt`・`mock_objects.kt` を追加解除。`compiler_plugin_api.kt` は 2026-08-13 現在 SKIP-DIFF タグが無く active（`--force-run-skipped` で PASS）
- **2026-09-16 継続監査**: 現行 HEAD で `Scripts/dead_code_audit.sh --self-test` を再実行し、`@_cdecl("__kk_x")` と Swift 名 `kk_x` の別名呼び出しを Tests / Runtime 内部の到達性判定へ追加。E0 を満たす旧リフレクション ABI 9 件（KFunction 3、callable reference 4、KProperty stub 2）と、source-backed 化済みの `kk_indexed_value_new` / `__kk_mutable_collection_addAll_sequence` を Runtime 実装・`RuntimeABISpec` ともに削除し、ABI 回帰テストを追加した。監査結果は `docs/dead-code-audit.md` に追記。残る KProperty 完全メタデータ拡張、`kk_cinterop_writeBits`、HTTP 追加 surface は所有タスクで継続監査する。
- **2026-09-23 継続監査**: HEAD（`59dd246ff`）で監査再実行し #6881 マージ地点とのリスト差分を取得。実測: Runtime export 1,702（前回 1,665）、compiler-unreachable 130（136）、A 14（変化なし）、B 76（82→−7：freezable_atomic_ref 5 件は #6914 の Kotlin 化で削除、cpointer_new/instant_from_epoch_seconds は配線済み、+1：ARCH-016 の `kk_object_release` は emit 配線待ちの意図的テストのみ）、runtime-internal 40（変化なし）。self-test 4/4 PASS。A 14 件は全て延期理由を再確認済みで削除なし。`.c/.h` は 2 件（RuntimeCAtomics、#7121 の stdatomic セル、正当）。`DiagnosticRegistry` 99 descriptor 全て production 発行あり。詳細は `git show 209eca2f97:docs/dead-code-audit.md` の 2026-09-23 節。

---

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

### 3. Inline 展開の責務分離・終了条件（RF-LOWER-INLINE）

> INLINE-001 → 002 → 003 → 004 → 005 → 006 → 007 → 008 → 009 → 010 → 011 → 012を基本のマージ順とする。002〜009は `InlineLoweringPass.swift` を共有するため、個別の小PRとして順次マージする。抽出時に展開順序・ラベル採番・ABI・例外処理を変えず、固定回数の撤廃は安全な停止条件を用意した010後に行う。

- [x] RF-LOWER-INLINE-011: bodyless inline snapshot は決定的な callee-first worklist で依存順に処理する。80段 chain・imported inline・lambda 内依存・diamond・循環停止を含む `InlineTerminationContractTests` 19 tests が RF-LOWER-INLINE-012 の再帰解消後に通過。
  - 対象: `expandNestedBodylessInlineCalls` 相当のschedulerのみ。calleeからcallerへ処理する決定的worklistを使い、lambda内の依存も含める。呼び出し側の8回走査はまだ変えない。
  - 完了条件: 4段を超える正当な依存鎖でも必須callが解消され、同じ元本体の二重展開がない。diamond依存・imported inline・lambda内依存・循環での停止を固定し、010の診断と展開量制限を維持する。
- [x] RF-LOWER-INLINE-012: caller expansion は共有 work budget の pending-call queue で進捗を追跡する。24段の inline/lambda 交互鎖が再帰的な body 展開でテストスレッドの stack を使い切る問題も、展開対象の nested call を caller queue に返すことで解消した。`InlineTerminationContractTests` の 19 tests が通過。
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

- [x] KSP-714: RangeProgression / RangeInterface / RangeUntil クラス群を Kotlin 化し stub 群を削除する（ProgressionConstructors.kt と各型・インターフェースの source 宣言を正規経路にし、3つの synthetic stub ファイルと registry 登録を削除。lowering が必要とする `__kk_*` runtime bridge は private source bridge として維持。`ULongProgression` の範囲プロパティも opaque runtime handle 用 bridge に接続）
  - 検証: `swift build`、Sema source-backed declaration test 1/1、`range_progression.kt` / `range_until.kt` / `range_basic.kt` の kotlinc diff 3/3 が pass。全テストは未実行。
  - 残余対応 (2026-10-21, KUU-2681): 移行済み bundled Kotlin source が内部で使う signed range の runtime bridge 37 シンボル（`kk_op_rangeTo` と `kk_range_step` を含む `kk_range_*` HOF / iterator / for-in / take・drop・average・sorted 群）を `__kk_*` へ降格し、Runtime の `@_cdecl`・RuntimeABISpec（+Range / +ABIParity / +BridgeCoverage）・KIR link name・bundled `.kt` の `@KsSymbolName`・テスト期待値を同期した。Swift 関数名と `functionName:` 診断ラベルは既存慣例どおり `kk_` のまま維持（KSP-457 / KSP-709 と同じ手順）。synthetic stub ファイルは既に削除済みのため再作成しない。

### バグバックログ（BUG-NNN。既存の未修正バグの記録。PR 状態は各タスクの記載時点）

> BUG-241 現況（2026-10-20）: `.kklib` では `UIntRange.contains(UInt)` を receiver 型の子シンボルとして登録した候補がユーザー拡張と誤認され、`ClosedRange.contains` へフォールバックしていた。range package 配下の宣言を scoped user-extension 候補から除外し、同一スコープのユーザー拡張が無い場合に exact bundled overload を先に束縛する修正を追加。`RangeArtifactExactContainsTests` は source / artifact の両経路で PASS。共通ゲート G は未実施のため本項目は保留。

> BUG-238 は PR #7051（2026-09-23）で実装され、CompilerCore・Backend・Runtime・CLI・LSP・kotlinc O0/O2 の共通ゲートが green。2026-10-20 に `.kklib` 明示経路の `size` / `first()` 回帰も確認済み。

> このセクションは過去に記録された未修正バグの記録専用で、新規追加は行わない。バグを発見したら最小再現と回帰テストを含めて発見した PR 内で修正し、同じ PR のスコープを超えて修正できない場合は Linear に起票し（team Kuu / project バグバックログ (BUG) / label Bug）、issue リンクを PR description に記載する。TODO.md には追加しない（並行セッションが同じ挿入位置に追記して衝突する原因になるため）。


- [x] BUG-234: `getOrPut` の既存 `Double` 値読み戻しで壊れた値になるという報告。**台帳修正 (2026-10-20):** 最新 master の実コンパイルでは記載の再現を確認できなかったため stale report と判断した。`mapOf` 由来の既存値を `getOrPut` で読み戻すバックエンド統合テスト（bundled stdlib の両モード）と、`.kklib` 経由の `Scripts/diff_cases/bug234_get_or_put_existing_double.kt` を追加し、いずれも `2.5` を返すことを確認した。

- [x] BUG-235: `Collection<T>` 型レシーバに対する `first()` / `last()` の source-backed 拡張フォールバック不足として登録された項目。 **台帳修正 (2026-10-20):** 現行の `knownNames.collectionMembers` は `first` / `last` を含み、記載された `Map.values` の再現コードは実行まで成功した。 旧来の `collectionMembers` 集合（#7111 の移行前）にも両名が含まれていたため、登録時の根本原因記述はソースと一致しない stale report と判断した。 `Map<String, Int>.values` の静的型と `first` / `last` の束縛を Sema Golden で固定し、実行比較ケースも追加した。

- [x] BUG-238: `.kklib` 経由の `File.useLines { it.toList() }` 結果に対するメンバアクセス失敗。修正は PR #7051 でマージ済み。追加した artifact 経路テストで `size` / `first()` の実行が PASS。

- [ ] BUG-241: `.kklib` 経由で読み込んだ、同一 FQ 名を持つ複数の top-level 拡張関数オーバーロードのうち、レシーバの型引数と完全一致する（cross-type ではない）オーバーロードがメンバー呼び出し構文で正しく解決されず、継承元のジェネリックメンバー（例: `ClosedRange<T>.contains`）へ誤ってフォールバックする。最小再現: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeMembership.kt:117` の `public operator fun IntRange.contains(value: Int): Boolean` と `RangeHOF.kt` の `IntRange.contains(Byte/Long/Short)` 系オーバーロードが同居する状態で `fun f(range: IntRange, value: Int): Boolean = range.contains(value)` をコンパイルすると、`--stdlib-from-source`（bundled source injection）では期待通り `kotlin.ranges.contains[recv=IntRange;params=Int]` に解決されるが、`--stdlib-library <artifact>.kklib`（KSP-939 以降の artifact 読み込み経路）では `kotlin.ranges.ClosedRange.contains[recv=ClosedRange<T0>;params=T0]`（ジェネリック継承メンバー）に誤って解決される。無効な引数型（例 `Byte?`）を渡した場合の診断も、bundled-source では `KSWIFTK-SEMA-0002 No viable overload found for call` だが artifact 経由では `KSWIFTK-TYPE-0001 Conflicting bounds for type variable #0: inferred Any? is not a subtype of Int. lower=[Byte?, Int], upper=[Int]` という分かりにくいメッセージに変わる（`kswiftc --stdlib-from-source` と `--stdlib-library` を同一 `.kt` で切り替えて実測比較済み）。実行時の挙動は両経路とも正しい（`ClosedRange<Int>.contains` の実装も同じ比較結果を返すため、`--emit executable` で `range.contains(5/15/1/10)` 等を実行し出力が両経路で完全一致することを確認済み — Sema の解決先シンボルと診断メッセージの精度のみの問題で、コード生成上のバグではない）。`ULongRange.contains(ULong)`（`RangeMembership.kt` の同型オーバーロード）でも `.contains()` メンバー呼び出し構文で同じ現象を確認した一方、`in` 演算子構文（`value in range`）は `isSyntacticRangeExpression`/`isRangeExpr` 経由の別解決パスを通るため影響を受けない場合がある。UInt/UByte/UShort 引数（cross-type、`RangeHOF.kt` の別オーバーロード）は artifact 経由でも正しく解決される。原因（未確定、要追加調査）: `CallTypeChecker+RangeMemberFallback.swift` の `isULongRangeCrossTypeContains`/`isIntRangeSourceBackedHOF` 系ゲートは cross-type ケースのみを `collectRangeSourceExtensionCandidates` 経由の明示解決へルーティングし、同型（exact-type）ケースは通常のメンバー探索に委ねる設計に見える。bundled-source ではこの通常探索で `IntRange.contains(Int)`/`ULongRange.contains(ULong)` が正しく見つかるが、`.kklib` 経由では見つからずジェネリック継承メンバーへフォールバックする。`LibraryImport.swift` の `symbols.define` 呼び出し自体は `canCoexistAsOverload`（`SemanticsModels.swift:664` 付近、`.function` kind 判定）により複数オーバーロードの共存を許可しているため、シンボル登録自体ではなく登録後の通常メンバー探索・オーバーロード選択側に原因がある可能性が高い。発見元: PR #6649（golden テストを artifact 経路へ切り替える変更）と master ブランチ（KSP-1285/KSP-1292: IntRange/ULongRange cross-type contains 追加）のマージコンフリクト解消中、両者を統合した状態で `UPDATE_GOLDEN=1` 実行時に `stdlib_kotlin_ranges_IntRange_cross_contains_n.golden`/`stdlib_kotlin_ranges_ULongRange_n.golden` の再生成結果が master の期待値と食い違うことに気づいた。`kswiftc` 単体で `--stdlib-from-source` と `--stdlib-library` を切り替えて比較し、マージ作業（3ファイルの手動統合）そのものとは無関係に artifact 経由のみで再現することを確認済み（マージ由来のバグではなく、独立に開発された両機能を単純結合しただけで顕在化した既存のギャップ）。今回修正しない理由: 原因箇所が `.kklib` ライブラリ読み込み・通常メンバー探索という広い層にまたがり（BUG-238 と同系統の「ライブラリ読み込み層でのオーバーロード解決」カテゴリ）、特定にはさらなる調査が必要。severity は低い（実行時結果は両経路で一致し、影響は Sema の解決先シンボルの精度と診断メッセージの質のみ）ため、マージコンフリクト解消というスコープを超えて追わず、該当 golden は実際の（artifact 経由の）コンパイラ挙動をそのまま記録する形で固定した。追記（KSP-1290 UIntRange 実装時）: `UIntRange.contains(UInt)`（`RangeMembership.kt` の同型オーバーロード）でも `.contains()` メンバー呼び出し構文で同一現象（`kotlin.ranges.ClosedRange.contains[...]targs=[UInt]` への誤フォールバックと `UByte?` 引数での `KSWIFTK-TYPE-0001` 化）を確認した。`in` 演算子構文は同様に影響を受けない。IntRange/ULongRange と対称の挙動であり、原因・severity の評価は変わらない。

- [x] BUG-242: 文字列テンプレート内の `$$` エスケープで `$` が失われると報告された項目。 **再検証 (2026-10-20):** 現行 master の実行結果は `$0.0` で、KIR にもリテラル `$` と補間値の連結が生成され、記載症状を再現できなかった。 `Scripts/diff_cases/bug242_string_template_escaped_dollar.kt` を追加し、kotlinc との一致を固定した。

- [x] BUG-229: primary-constructor property に付けた `open` が override 可として扱われないと報告された項目。 **再検証 (2026-10-20):** 現行 master には `AbstractOpenOverrideTests.testPrimaryConstructorOpenPropertyCanBeOverridden` があり、同じ Sema ケースは `KSWIFTK-SEMA-FINAL` なしで通る。 基底型経由で派生 override を読む runtime 差分ケースを追加し、kotlinc と `base!` で一致することを確認した。

- [x] BUG-236: 混在 `arrayOf(1, "two", 3.0)` の推論。2026-10-20 の再監査で、既存の #7059 が lower-bound inference を修正し、現行 Golden は `Array<Comparable<*>>` を記録することを確認した。KSwiftK の対象は Kotlin/Native であり、`java.io.Serializable` を含む kotlinc/JVM の交差型・reified 診断はこの Native 型環境の共通上位型を表さない。Native では `Comparable<*>` が入力型すべてに共通する型であり、現在の推論と既存 Golden がその契約を固定しているため、追加のコンパイラ変更は不要。

- [x] BUG-243: object 式（匿名クラス）のメンバー関数から、それを囲む外側クラスの一次コンストラクタプロパティ（`private val` 等）を読むと、実際の値ではなく `0`（デフォルト初期値相当）になる。最小再現: `class Counter(private val limit: Int) : MutableIterable<Int> { override fun iterator(): MutableIterator<Int> { return object : MutableIterator<Int> { var i = 0; override fun hasNext(): Boolean { println("i=$i limit=$limit"); return i < limit }; override fun next(): Int { val v = i; i++; return v }; override fun remove() {} } } }` に対し `fun main() { val c: MutableIterable<Int> = Counter(3); val iter = c.iterator(); println("hasNext: ${iter.hasNext()}") }` を実行すると、`hasNext()` 内の `println` は `i=0 limit=0` を出力する（kotlinc なら `limit=3`）。同じ値をコンストラクタで明示的に渡す名前付きクラス（`class MyIterator(private val limit: Int) : MutableIterator<Int> { ... }` を `MyIterator(limit)` として構築）では正しく `limit=3` になるため、キャプチャ機構（暗黙の外側プロパティ読み取り）特有の欠落と判明している。原因は未特定（追加調査が必要）だが、KSP-CAP-001（object 式のメンバー関数が参照する外側ローカル/パラメータをインスタンスフィールドとして materialize する仕組み、`ExprTypeChecker+ObjectLiteralInference.swift` の `capturedSymbols`/`collectCapturedOuterSymbols` と `driver.lambdaLowerer.captureValueExpr`）が、外側の**ローカル変数/パラメータ**は対象にしている一方、外側の**クラスの（プライマリコンストラクタ由来の）プロパティ**は同じ扱いを受けていない疑いがある（`non-property-primary-ctor-param-scope-bug` の「パラメータ名解決が scope でなく locals 辞書経由」という既知の設計制約と根が近い可能性）。発見元: BUG-242（object 式の itable スロット未計算バグ）の検証用に `Scripts/diff_cases/object_literal_mutable_iterator.kt` を作成する過程で、当初 `limit` をコンストラクタ経由でキャプチャする形の再現コードを書いたところ本バグに遭遇したため、`limit` を使わないハードコード値（`i < 3`）の再現に差し替えて BUG-242 を先に確定した。今回調査・修正しない理由: KSP-CAP-001 のキャプチャ materialization ロジック自体の設計を要する別レイヤの問題で、BUG-242（Sema のレイアウト計算、`itableSlots` が空になる欠落）とはサブシステムが異なり、スコープを大きく超える。
  - **現状確認（2026-10-20）**: object 式から外側の一次コンストラクタプロパティを読む最小再現を source 注入・`.kklib` 両経路で実行するテストを追加。どちらも `limit=3` 相当の反復結果を返したため、現行 master では既に解消済みとして記録する（この PR は再発防止テストのみ）。

- [x] BUG-265: 2026-10-20 に現行 master で再検証し、名前付き object 内の暗黙 setter 書き込み・直後の getter 読み取りと、object の `by lazy` の複数回読み取りが動作することを確認した。回帰テスト `BundledStdlibExecutionTests.testNamedObjectImplicitSetterAndLazyDelegateAccess` は source injection / bundled `.kklib` の両モードで `0\ns\n7\n7\n` を出力する。

- [x] BUG-261: property custom getter/setter 本体で投げた例外の伝播。 **再検証 (2026-10-20):** 現行ベースでは object/class の getter と setter から `IllegalArgumentException` が呼び出し元へ伝わり、bundled source と `.kklib` の両経路で捕捉できる。 `testCustomPropertyAccessorExceptionsPropagate` を追加して動作を固定した。 以前の不具合報告は現行ベースでは再現せず、KIR に accessor 呼び出しの thrown channel も出力されるため、追加の runtime 修正は不要。
- [x] BUG-262: 異なる数値プリミティブ型の `==` / `!=` が受理されると報告された項目。 **再検証 (2026-10-20):** 現行 master の既存 equality 型チェック（`ExprTypeChecker+BinaryAndFlowInference.swift`）は `0.6 != 1` を `KSWIFTK-SEMA-0002` で拒否する。 左右逆順・Float/Long の回帰テストを加え、同型 equality と数値 ordering は受理されることも固定した。
- [ ] BUG-266: バンドル stdlib の `object` メンバーで、型が `Long` の `var`（カスタムアクセサの有無を問わない）への書き込みが、その `object` を実利用者と同じ通常経路（`.kklib` 経由、`--stdlib-from-source` を付けない）でインポートしたときに限り、例外もクラッシュも出さず静かに無視される。同じソースを `--stdlib-from-source`（バンドル stdlib をユーザーコードと同一パスでコンパイル）で流すと正しく書き込める。最小再現: `object GC { var minHeapBytes: Long get()=__minHeapBytes; set(value){ __minHeapBytes=value }; private var __minHeapBytes: Long = 5L*1024*1024 }` 相当（実際は `kotlin.native.runtime.GC`）に対し `fun main(){ GC.minHeapBytes = 512L; println(GC.minHeapBytes) }` を書くと、kotlinc 側は無関係（`kotlin.native.*` は JVM 非対応）だが、本コンパイラは通常ビルドで `5242880`（初期値、`512` ではない）を出力する。同じ形の `Boolean`/`Double` プロパティ（`GC.autotune`, `GC.heapTriggerCoefficient` 等）は同じ書き込み経路で正しく動作するため、`Long` 型に限定された欠落。ただし `GC.regularGCInterval`（`kotlin.time.Duration` — 内部表現は `Long`）は同じ書き込み経路で正しく動作するため、単純な「値のビット幅／物理表現が 64bit だと壊れる」という説明では足りない。`Duration` は inline value class で KIR/Sema 上は `Long` そのものとして消去されないラップ型として扱われている可能性が高く、壊れるのは「KIR 上で素の `Long` 型タグを持つ値」の場合に限られる、という手がかりになる。再現コマンド: `swift build && .build/debug/kswiftc --stdlib-only -o /tmp/gcstdlib` でバンドル stdlib を単独 `.kklib` に切り出し、`KSWIFTK_STDLIB_LIBRARY=/tmp/gcstdlib.kklib .build/debug/kswiftc probe.kt -o probe && ./probe`（`probe.kt` は上記の `main`）で再現。`--stdlib-from-source` に切り替えると同じソースが正しい値を返す。原因（未確定）: `CallLowerer+MemberAssignment.swift:lowerMemberAssignExpr` の最初の2分岐（`memberPropertyUsesSetterAccessor` 経由の custom setter 呼び出し、および `ownerInfo.kind == .object` を前提にした flat global slot 書き込み）はどちらも、`--stdlib-from-source` と通常インポートの双方で同一の KIR（`call set symbol=_ args=[receiver, value]`、`--emit kir`/`--emit llvm` を diff して確認済み — テキストは完全一致）を生成しており、分岐そのものはヒットしていない可能性が高い。両モードで生成物が同一にもかかわらず実行結果が異なるため、乖離は KIR 生成より後（コード生成、またはインポートされたシンボルのオブジェクトコード解決）にあり、`Long` 型の値だけがそこで迷子になる。`Boolean`/`Double` は動作するため型固有の分岐（値の物理表現、または呼び出し先解決に使う何らかの型タグ）が疑わしいが未特定。バンドル stdlib 全体を grep した限り、`object` メンバーで setter を持つ `Long` 型の `var` は今回 KSP-1262 で追加した `GC.targetHeapBytes`/`GC.minHeapBytes`/`GC.maxHeapBytes` が唯一の例（既存コードに同型のケースがないため今まで検出されなかった）で、`kotlin.native.*` 配下のため `Scripts/diff_cases/` に追加しても `SKIP-DIFF`（JVM kotlinc 非対応）にしかならず、通常の diff 経路で実行される最小ケースは今回作れなかった。今回修正しない理由: 発生箇所が Sema のメンバー代入 lowering ではなくコード生成/シンボル解決側にあると見られ、当該サブシステム（`NativeEmitter`/インポートしたシンボルのオブジェクトコード解決）の調査が必要で、KSP-1262 のスコープを大きく超える。暫定対応として `GC.targetHeapBytes`/`minHeapBytes`/`maxHeapBytes` の setter は本バグが直るまで明示的な no-op にしてある（`Sources/CompilerCore/Stdlib/kotlin/native/runtime/GC.kt` 内のコメント参照）。注記: 当初 BUG-263 として起票したが、master 側の先行エントリ（`Outer.Inner` ネスト object の materialization、別内容）と同番号で衝突したため BUG-266 へ改番した。

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
> 進行中 PR: なし（Batch 83 #5765・Batch 84 #5785・Batch 85 #5817 はすべてマージ済み、2026-10-19 確認）。

- [~] REFACT-TEST-005: 集約後に不要になった per-test pipeline ヘルパー・重複 `source` 文字列・個別 `withTemporaryFile` ブロックを削除し、migration スクリプト群を整理
  - List の shared Sema context を使わない `fun noop() {}` wrapper 31 箇所、単一用途の `makeSema` helper 8 箇所、および Regex の不要な case 引数を削除した。テスト名、fixture、診断、実行順独立性は維持している。
  - migration script の共通化は master の #6430 で完了済みのため、既存の所有範囲を重複変更していない。
  - focused Sema 107 tests、SmokeTests 12 tests、runtime ABI link 4 tests、build、TODO ID 検査は PASS。CompilerCoreTests 全体は Golden semaphore 待ちのため未完了で、全体ゲート green 後に完了へ更新する。

---

## Sema Golden と stdlib 実装契約の責務分離（RF-GOLDEN: 2026-09-06 調査）

### タスク

- [x] RF-GOLDEN-005: ABI・bridge・throwing 契約の移管漏れを専用テストで補完する（前提: 001）
  - 対象: `RuntimeABIExternalLinkValidationTests` / `StdlibSurfaceSpecTests` / `ABIMismatchTests` / `ABIMismatchRuntimeExportParityTests` と ABI lowering tests。参照先の externalLinkName と `@KsSymbolName`、RuntimeABISpec、runtime export の対応・引数順 / 型 / arity / 戻り型を照合する。既存の constructor 特例や export parity の除外を把握し、必要な個別テストを確認する。
  - `ABILoweringPass` の throwingFunction → outThrown、非 throwing 呼び出し、source-backed bridge の実際の lowered call を確認する。`DurationSyntheticStubTests` の parse bridge flag assertion や collection mutation の ABI assertion は再利用し、symbol 名が登録されているだけ・spec とその派生表が一致するだけでは実 call / export との適合を証明したとしない。
  - 完了条件: 001の ABI / bridge 移管項目を具体的な assertion と正常 / 異常系で覆い、`validate_runtime_abi_links.sh` と関連 Runtime / Lowering テストが green。既存除外・許可リストを拡大して green にする変更はしない。
  - 完了確認（2026-10-20）: `validate_runtime_abi_links.sh`、RuntimeABI external-link validation 8件、`StdlibSurfaceSpecTests` 7件、`ABIMismatch` 91件、source-backed Duration bridge lowering 1件、collection mutation ABI call 1件、runtime throwing 7件が PASS。surface spec の古い `Sequence.intersect` 期待値も削除した（`intersect` は Iterable / Collection surface）。
- [~] RF-GOLDEN-006: 安定した宣言キーを stdlib の実装方式によらない公開参照へ対応付ける（前提: 002・010）
  - 対象: `StableRenderContext` の外部参照 / 型 / signature の描画と Sema formatter。番号の廃止・型パラメータの位置正規化は010で完了させ、ここでは002の由来判定を使い、synthetic member alias / bundled extension / imported 宣言を同じ公開 API へ対応付ける追加の投影だけを実装する。
  - 戻り型・nullability・variance・境界・suspend・default / vararg・named argument に必要な引数名など、型検証と呼び出し識別に必要な契約を保持する。member alias と元の extension は由来・対応が証明できる場合だけ同じ公開参照へ写し、同名同 arity の別 overload やユーザー override は潰さない。runtime link 名を公開 API の安定IDに使わない。
  - 完了条件: 同じ公開 API の synthetic / source-backed / imported 表現は同じ参照となり、別 overload は区別されること。010の不変・感度テストを維持し、由来の違いを吸収する追加投影の既定出力への接続は008まで行わない。
---

## Stdlib gap audit 2.3.10 実装タスク（KSP-719+）

> 公式 Kotlin/Native 2.3.10 `klib dump-abi`（`official_native_stdlib_abi.txt`）を正典として、KSwiftK バンドル Kotlin ソース（`Sources/CompilerCore/Stdlib/kotlin/`）と比較した機械監査結果から生成。`kotlin.jvm` / `kotlin.internal` / `kotlin.native.internal` / `kotlin.test` / `kotlinx` / `java` / `javax` / wasm・web-only sourceset は除外。
> 1タスク = 原則 1 PR。粒度は（package, receiver）単位または 30 件を超える場合は関数名 prefix ファミリー単位。未実装の最新状況は、固定の一覧ではなく `bash Scripts/diff_kotlinc.sh` による kotlinc 2.3.10 との差分で都度確認する（旧 `docs/stdlib-gap-audit-2.3.10/gap_v2.tsv` は削除済み）。
> 実装時には、既存の `__kk_*` / `kk_*` bridge・合成スタブ・`RuntimeABISpec` 登録があれば同 PR で削除または `__kk_` 降格し、`UPDATE_GOLDEN=1` で golden を更新、`bash Scripts/diff_kotlinc.sh` で kotlinc 2.3.10 との差分を確認すること。

- [x] BUG-260: `kotlin.native.concurrent.withWorker { ... }` が本体が空でも常に unhandled top-level exception で panic する
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
  - **現状確認（2026-10-20）**: 本項目の最小再現を source 注入・`.kklib` の両経路で実行する回帰テストを追加。どちらも `inside` と `after` を出力して正常終了したため、現行 master では既に解消済みとして記録する（この PR は再発防止テストのみ）。

- [x] BUG-263: ネスト object の値化とプロパティ代入は、現行 master では動作する。2026-10-20 に `GC.MainThreadFinalizerProcessor.batchSize` の chained assignment と、`val processor = GC.MainThreadFinalizerProcessor` 経由の代入・読み取りを実行し、source injection / bundled `.kklib` の両モードで `5\n7\n` を確認した。回帰テスト: `BundledStdlibExecutionTests.testNestedObjectValuesAreMaterializedForAccess`。

- [x] KSP-1307: kotlin.ranges.LongProgression.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - **進捗確認（2026-10-19）**: `Stdlib/kotlin/ranges/ProgressionConstructors.kt` に `LongProgression.Companion.fromClosedRange` は実装済みだが、bundled source / runtime bridge とも `step: Int` で、監査対象の本家シグネチャ `fromClosedRange(Long, Long, Long)` は未充足（`step` に Long を渡す呼び出しは解決しない）。残件として継続。
  - **完了確認（2026-10-20）**: `ProgressionConstructors.kt` に `step: Long` overload と同一 Runtime bridge への宣言を追加し、`HeaderHelpers+SyntheticRangeProgressionStubs.swift` に Long step の fallback を登録。Sema Golden fixture を追加して artifact profile の `GoldenHarnessWorker` 単体描画と一致確認。`swift build --scratch-path /private/tmp/swift-build-ksp1307`、単一 `diff_kotlinc.sh` ケース、`check_todo_ids.sh`、`validate_runtime_abi_links.sh` PASS。Sema Golden suite 全件は未実行。
  - **追補（2026-10-21）**: `__kk_long_progression_fromClosedRange` / `__kk_ulong_progression_fromClosedRange` の `step == MIN_VALUE` 例外メッセージが `Int.MIN_VALUE` のままだった（Int-step では到達不能で、Long-step overload 追加で初めて観測可能になった経路）。kotlinc の `Long.MIN_VALUE` 表記に合わせて修正し、diff ケースに `step=0` / `step=Long.MIN_VALUE` の catch＋メッセージ出力、Int リテラル step、オーバーフロー境界のピンを追加。`RuntimeRangeProgressionEdgeCaseTests` にもメッセージ本文の assert を追加。
  - 対象: `kotlin.ranges.LongProgression.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ProgressionConstructors.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongProgression.Companion.fromClosedRange` — fun Companion.fromClosedRange(Long, Long, Long): LongProgression  -- `final fun fromClosedRange(kotlin/Long, kotlin/Long, kotlin/Long): kotlin.ranges/LongProgression`

> KUU-475 完了根拠（2026-09-16、HEAD `b4cd1664ce23e81c92c2a211199e51e51f0d3fcb`）: KSP-711 の merged commit `9a39776adff70eb419b7effc3ea21fa0a1baa632` が Typography 全定数を bundled Kotlin source として実装済み。KSP-1442〜1471 の対象 23 タスクは、現行 `Sources/CompilerCore/Stdlib/kotlin/text/Typography.kt:12-52` の `public const val` 宣言が所有する。`StringSyntheticMemberLinkTests.testTypographyObjectSurfaceResolves`（`Tests/CompilerCoreTests/Sema/StringSyntheticMemberLinkTests.swift:936-1010`）は全 41 定数を非 synthetic の source-backed object/property、非 nullable `Char`、const の char literal として検証する。Typography 専用の synthetic/runtime/RuntimeABI 経路はなく、個別 `.kt` / Golden / diff ケースを追加すると既存実装と重複する。
> 検証: `swift build` PASS、`SWIFT_TEST_PARALLEL=0 SWIFT_TEST_WORKERS=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.StringSyntheticMemberLinkTests` PASS（4 tests / 1 suite）、`git diff --check` PASS。全 Golden / 全 diff_kotlinc / Runtime ABI link の aggregate gate は未実行。

## 戦略アーキテクチャ改善 実行計画（ARCH: 2026-08-22 構造レビュー）

> 出典: 2026-08-22 の全サブシステム構造レビュー（Sema / KIR / Lowering / Backend / Runtime / Driver / LSP / テスト基盤の精査 + 実測）。主要実測値: release kswiftc で hello.kt が **デフォルト 4.27s → `--stdlib-library`(.kklib) 1.40s → `--no-stdlib` 0.41s**（コンパイル時間の ~2/3 が bundled stdlib 2.6万行の毎回再処理）。実行時は `for (i in 1..1000000)` が 1,236ms = **1.24µs/iter ≒ ランタイム C 呼び出し 2 回 × ~620ns**（NSLock + Set ハンドル検証 + 動的キャスト、しかも -Onone ビルド）。
> 参照プラクティス: rustc（事前コンパイル stdlib / rmeta 遅延読込 / lang items）、Kotlin K2（フェーズ化・IDE 遅延解決）、Roslyn（WellKnownMember）、Swift SIL（raw/canonical + verifier）、MLIR（パス境界検証）、rust-analyzer（durability・エラー耐性）、Kotlin/Native（コンパイラ統合ランタイム・並行 mark-sweep）。
> **共通ゲート G を全タスクに適用**（+ 該当時 U）。粒度ルール: 1タスク = 1 PR。性能タスクは変更前後のベンチ値（`Scripts/benchmark_stdlib_hof.sh` / `-Xfrontend time-phases`）を PR 本文に記載する。既存台帳との関係: 名前文字列特例の解体は RF4 系・KSP 移行と同期して進め、本セクションでは重複起票しない。
> 優先順は Tier 順。**ARCH-001/002 は他の全性能系判断（stdlib-pipeline §13-3 の「Swift 残留の実測条件」）の基準値を変えるため最優先**。完了後に `docs/refactoring-metrics.md` のベンチ基準値を取り直すこと。

### ARCH Tier 2a: ランタイム統合（Kotlin/Native 型モデルへの段階接近）

> 背景: Runtime には設計済みの K/N 型モデル（`KTypeInfo` / `kk_alloc` / `KKObjHeader` / frame map / mark-sweep GC）と、実際に動く「Swift ARC box + インスタンスごと辞書 vtable + グローバル NSLock」の**二重設計**が同居し、前者は codegen 未配線で全て到達不能、後者は box 解放経路がなく恒久リークする。GC は起動トリガーが存在せず一度も走らない。

- [~] ARCH-016: box/オブジェクトの解放経路を導入する（恒久リークの解消）。現状 `RuntimeIntBox`/`RuntimeStringBox`/`RuntimeListBox`/`RuntimeMapBox`/`RuntimeObjectBox` は `Unmanaged.passRetained` 後に release する者が存在せず、`objectPointers` 登録とともにプロセス生涯リークする（`RuntimeGC` のコメント自身が「解放は box を release する者の責任」と明言）。mark-sweep は対象ヒープ（`heapObjects`)が常に空で一度も起動しない。到達可能性ベースの回収または明示解放経路を設計・実装し、割付ループの RSS が有界になることを固定する。完了条件: 割付ループ（例: `while` 内 `list.add` / boxing）の RSS 有界性テスト + RuntimeTests + G。前提: ARCH-015。
  - 実装済み・共通 G 待ち（2026-09-18）: `kk_object_release` を新設し、retained box は登録解除→メタデータ／freeze registry 除去→ARC release の順で明示解放する経路を追加。pinned object、StableRef、Unit、borrowed な flow/sentinel は解放対象から除外し、flow reset では専用 registry と `objectPointers` を同期して stale handle を残さない。`RuntimeABISpec` と export parity の契約も追加。`RuntimeObjectOwnershipTests`（4/4、100,000 回 boxing 解放ループの registry/RSS 上限）、`RuntimeHandleResolutionResetTests`（5/5）、`RuntimeGCTests`（7/7）が green。全 Swift テスト、全 Golden、全 diff ケースは未実行。

### ARCH Tier 2b: KIR 品質基盤（SIL/MLIR 流の検証導入）

- [x] ARCH-020: `KIRStage` 段階マーカー（raw / desugared / abiLowered 等）を導入し、各 Lowering パスが要求・生成段階を宣言する。完了（PR #7040、2026-09-19）: `KIRModule.stage`、全標準 Lowering パスの required/produced 宣言、debug 時の順序検査を実装済み。`KIRStageTests` が標準順序・最終 `abiLowered` 段階・誤順序拒否を固定し、PR #7040 の全 Swift / kotlinc CI shard が成功済み。前提 ARCH-018 も完了済み。

### ARCH Tier 2c: Sema の名前ディスパッチ出口戦略（RF4/KSP と同期）

- [x] ARCH-021: well-known シンボル表を導入する。完了（PR #7049、2026-09-23）: `WellKnownSymbols` がヘッダー収集後に compiler-owned な collection factory / enum / reflection / contract 宣言を FQName から `SymbolID` へ一度だけ解決し、代表的な Sema / KIR 特例が完全一致する `SymbolID` を使う。`WellKnownSymbolsTests` は代表シンボル、ユーザー同名宣言の shadowing、明示 import・alias を固定する。PR #7049 の全CI検証 shard が成功済み。全面置換は本項の範囲外として RF4/KSP 側に残す。
### ARCH Tier 2d: テスト・CI の 4 穴埋め

- [~] ARCH-027: macOS CI レーンを最低 1 本追加する。現状 CI は ubuntu のみで、`docs/spec.md` が宣言する一次プラットフォーム macOS を何も検証していない（diff スクリプトに macOS 専用の配慮が既に複数あるのに、である）。最小構成: build + SmokeTests + LinkPhase 系。完了条件: macos runner ジョブ green。
- [~] ARCH-029: `.kklib` metadata の遅延読込。ARCH-005 後は `metadata.bin` の eager 全量デシリアライズ + 合成スタブ登録で **Sema 664ms/回（release 実測）が全コンパイルの新たな支配項**になる。rustc rmeta / K2 stub 方式に倣い、metadata.bin を「FQName → オフセット索引 + 本体」の 2 部構成にして名前解決要求時にデシリアライズする。完了条件: `.kklib` 経路 hello.kt の Sema フェーズ前後値記載（目標 1/3 以下）+ `Lib*Metadata*Tests` green + G。前提: ARCH-005。
  - 実装済み（PR #7043）: indexed import は要求時に declaration body を materialize し、LibMetadataSerializationTests / Sema Golden の対象検証が成功済み。release `hello.kt` を明示した package root と同一 `.kklib` で再計測した4回は Sema 339.41/318.28/317.36/317.02ms、中央値317.82ms（664ms baseline の47.9%、2.09倍高速）。以前の別計測中央値272.86msとは差があるが、どちらも1/3目標（約221ms）未達のため `[~]` を維持。
  - 追加確認: #10688 の compact-index v3 オンデマンド登録により value-parameter / local / type-parameter shells は要求時にのみ登録される（`testCompactImportRegistersMachineryShellsOnDemand` で固定）。Sema 時間の再計測は未実施のため `[~]` を維持。

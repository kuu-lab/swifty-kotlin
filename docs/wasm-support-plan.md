# Kotlin/Wasm フルサポート メガプラン

> ステータス: M0/M1 の MVP を実装済み（後述「実装ステータス」節参照）。残りは引き続き計画段階。
> 対象読者: KSwiftK に wasm ターゲットを追加する作業者向けの総合ロードマップ。

## 実装ステータス（2026-10 時点）

**済み（M0 + 縮小版 M1）**:

- `TargetTriple` に `wasmWASI`（`wasm32-unknown-wasi`）/ `wasmJS`（`wasm32-unknown-js`）と `isWasm` / `isWASI` / `isWasmJS` を追加（`CompilerTypes.swift`）。`--target wasm32-wasi` 等の 2 セクション綴りを受理し canonical 化（`CLIParser.swift`）。未対応ターゲットの silent host fallback を廃止し診断化。
- `CompilerBackend/Wasm/` に自前の wasm バイナリエンコーダ＋エミッタを新設: `WasmModule.swift`（LEB128、type/import/func/table/memory/global/export/elem/code/data/name 各セクション）、`WasmEmitter.swift`（モジュールパス、関数/helper/stub index 管理、`_start` 生成）、`WasmEmitter+Function.swift`（KIR → 構造化制御フロー lowering）、`WasmEmitter+Runtime.swift`（ランタイム helper / builtin op テーブル）。
- `CodegenPhase` が wasm ターゲット時に `WasmEmitter` へ分岐し `.wasm` を `CompilationContext` に格納。`LinkPhase` は wasm 出力をネイティブリンク対象から除外。
- WASI MVP が Node `node:wasi` 上で実行可能: `_start` + `proc_exit`、`fd_write` による `print`/`println`（bundled stdlib の `kotlin.io.println`/`print` は raw WASI helper にルーティング）。整数四則・比較・分岐・while/for ループ・再帰・直接呼出・文字列リテラル出力が動作。
- 未実装ランタイム callee はゼロ返し stub を生成し、件数＋名前を warning で報告（hello world で ~141 件。診断される限り silent な誤動作ではない）。
- テスト: `Tests/CompilerBackendTests/Codegen/WasmCodegenTests.swift`（5 件。モジュール構造・制御フロー・stub 診断・Node WASI 実行）。

**計画からの意図的な偏差**: 現 MVP は計画案 B（WasmGC）ではなく **linear-memory + 全値 i64** 表現。理由は「エミッタ/ドライバ配管と KIR→wasm 制御フロー lowering を先に実証し、オブジェクトモデル確定（M2）と同時に WasmGC へ移行する」段階戦略。i64 一本化により boxing は現状 identity（タグ付き整数スキームは M2 でオブジェクトモデルと共に導入予定）。

**未着手（M1 残 + M2 以降）**: WasmGC（struct/array/ref 型）、本物のオブジェクト/vtable/`is`/`as`、例外の完全な thrown 経路、stdlib Kotlin 化、`kotlin.wasm` パッケージ、wasmJs 全般（externref/import/`@JsFun`/`.mjs` glue/`@JsExport`）、Promise/`.d.ts`、wasm `.kklib`・incremental・CI レーンの拡大（下記のとおり `DIFF_BACKEND=wasm` の starter レーンは導入済みだが、`// DIFF_WASM` マーカー付き MVP ケースのみ対象）。

## 0. ゴール定義

「Kotlin/Wasm フルサポート」= 以下をすべて満たす状態。

1. `kswiftc --target wasm32-wasi <files>.kt -o app.wasm` で standalone `.wasm` を生成し、`wasmtime` / `wasmtime run` で実行できる（wasmWasi 相当）。
2. `kswiftc --target wasm-js <files>.kt -o app` で `.wasm` + `.mjs` glue を生成し、Node.js / ブラウザで実行できる（wasmJs 相当）。
3. `kotlin.wasm` / `kotlin.js` 相互運用 API（`@JsFun`, `@JsModule`, `@JsQualifier`, `@JsName`, `@JsExport`, `js()`, `JsAny`/`JsArray`/`JsString`/`JsReference`, `kotlin.wasm.unsafe.*`）が利用できる。
4. stdlib（collections, text, coroutines など）は wasm ターゲット上でネイティブと同等の意味論を持つ。
5. `.kklib` ライブラリを wasm ターゲット向けに emit / import できる。
6. CI に wasm 回帰レーン（wasmtime / Node 実行 diff）が常設される。starter 版として `nightly-full.yml` の `verify-wasm` ジョブが `DIFF_BACKEND=wasm` で `// DIFF_WASM` 付きケースを node:wasi / wasmtime の両エンジンで実行する（`Scripts/diff_kotlinc.sh` の backend レーン。マーカー集合は実装済み MVP に合わせて拡大する）。

非ゴール（明示的に除外）: WASI threads / wasm atomics、wasm64、Emscripten ABI、上流 Kotlin/Wasm との .klib バイナリ互換（KSwiftK 固有 ABI でよい）、Compose/Web UI フレームワーク。

## 1. 現状調査サマリ

### 既に存在する資産

| 資産 | 場所 | wasm での価値 |
|---|---|---|
| expect/actual 完全実装（imported expect との pairing, `actual typealias`, `@OptionalExpectation`, common-module mode） | `Sema/DataFlow/ExpectActual.swift` | wasm 用 actual を `Stdlib/wasm/` に置ける |
| `.kklib` の `target` フィールド + import 時 triple 検査 | `LibraryDiscovery.swift:291-314` | wasm artifact の分離が済んでいる |
| `external` + `@KsSymbolName` の stdlib ブリッジ機構 | `HeaderHelpers.swift:157`, `CallLowerer+ResolvedCallEmission.swift:958` | wasm import バインディングの原型 |
| kotlin.js アノテーションの Sema 検証（JsExport/JsStatic/JsFileName） | `JsExportValidation.swift` ほか | wasmJs でそのまま拡張 |
| JVM バックエンドの並列パイプライン先例 | `EmitMode.isJVM`, `JVMFrontendPhase`, `CompilerBackend/JVM/`（classfile writer 1.4k 行） | バックエンド追加の構造モデル |
| CPS ベース coroutine lowering（stackful 機構なし） | `CoroutineLoweringPass` + `RuntimeCoroutine*` | wasm スタック非公開でも動く設計 |
| outThrown チャネルによる例外伝播 | `NativeEmitter+ThrownChannelEmission.swift` | wasm EH 非依存の例外をそのまま移植可能 |
| `OsFamily.WASM` / `CpuArchitecture.WASM32` / `#if os(WASI)` の seam | `Stdlib/kotlin/native/Platform.kt`, `RuntimePlatform.swift` | 報告面の接続点 |
| BundledStdlib のソースセット選択（`jvm/` 除外 + manifest 駆動の JVM stdlib） | `Driver/BundledStdlib.swift:54`, `Stdlib/jvm/manifest.json` | wasm ソースセットのモデル |

### 主要ギャップ（ブロッカー順）

1. **ランタイムの言語**: `Sources/Runtime` は Swift 69k 行・~2,000 `@_cdecl` 関数・Foundation/Dispatch/pthread 依存。wasm にはそのまま持ち込めない（Swift→WASI でも Dispatch/大半の Foundation が無い）。**再実装が本プロジェクトの最大コスト。**
2. **値表現が 64bit ポインタ前提**: i64 handle + タグ付きポインタ（`RuntimeHelpers.swift:9-52`）、`ptrtoint` vtable、実アドレス keyed GC。wasm32/WasmGC では全面再設計。
3. **wasm バックエンド皆無**: `LLVMInitializeWebAssembly*` 未バインド（`LLVMCAPIBindings+Loading.swift:266`）、ホストフォールバックが無診断（`NativeEmitter.swift:549-557` — 要修正）、wasm module writer なし。
4. **リンク経路がホスト専用**: `swiftc`/clang driver、`-dead_strip`、autolink stub、`main(argc,argv)` + `write(2)` entry（`LinkPhase.swift`, `LLVMEntryPointObjectEmitter.swift`）。
5. **kotlin.wasm API 表面ゼロ**: `@JsFun`, `wasmImport`, `JsReference`, `JsAny` 系、external 宣言のユーザ解放（`KSWIFTK-SEMA-0008` が禁止中）。
6. **プラットフォーム概念の欠如**: `TargetTriple` は自由形式文字列、`EmitMode.isJVM` が唯一の discriminator。`CompilationTarget` が必要。

### 戦略的判断: バックエンド方式

| 案 | 内容 | 評価 |
|---|---|---|
| **A. LLVM wasm32 linear-memory** | 既存 KIR→LLVM に wasm triple を通し wasm-ld でリンク。ランタイムを C で再実装 | 既存パイプライン再利用だが **WasmGC/JS interop が作れず「Kotlin/Wasm」にならない**。却下 |
| **B. KIR → 自前 WasmGC emitter**（推奨） | Lowering 済み KIR を wasm binary writer で出力。GC はエンジン任せ | 上流 Kotlin/Wasm と同モデル。Lowering（coroutine CPS, data class, delegate…全言語機能）を全再利用。JVM writer 先例あり |
| C. AST→wasm 別パイプライン（JVM 方式） | `WasmFrontendPhase` で KIR を bypass | JVM 同様に lowering の再実装が巨大。却下 |

**推奨構成**: `EmitMode` を拡張せず `--target` を `CompilationTarget`（native/jvm/wasmWasi/wasmJs）に格上げし、KIR+Lowering は共通、`CodegenPhase` で `WasmEmitter`（新規）に分岐。`CompilerBackend/Wasm/` に wasm binary writer（LEB128, セクション, GC 型, name section）を新設。

**ランタイム戦略**: Swift Runtime の移植はしない。**「ランタイムの Kotlin 化」** — kk_* の意味論を `Stdlib/kotlin|wasm` の Kotlin 実装 + 最小 wasm intrinsic 層（メモリ確保, JS/WASI host import, 文字列 primitive）へ段階移行。ネイティブ側は無変更。上流 Kotlin/Wasm も stdlib ほぼ Kotlin + 少数 intrinsic の構造。

## 2. フェーズ構成

```
M0 基盤   : CompilationTarget 導入、--target wasm 受理、writer 骨格
M1 最小   : hello world .wasm（wasmWasi、wasmtime で println）
M2 コア言語: クラス/継承/generic/lambda/when/例外 — diff_cases の言語系が wasm で走る
M3 stdlib : 文字列/コレクション/数値 — Kotlin 化ランタイムの本丸
M4 高度   : coroutine/reflection 相当/lazy/delegate/enumEntries など
M5 wasmJs : externref 型系、external→import、@JsFun/js()、.mjs glue、exports
M6 相互運用: kotlinx.coroutines on JS event loop、JsPromise、JsArray 系、.d.ts
M7 成熟   : .kklib wasm、incremental、LSP、最適化 pass、CI 常設
```

### M0 — ターゲット基盤（1〜2 PR）

- `CompilationTarget` enum（`native(TargetTriple)` / `jvm` / `wasmWasi` / `wasmJs`）を `CompilerTypes.swift` に導入。`TargetTriple` はネイティブ側に残す。`--target wasm32-wasi|wasm-js|wasm32-wasi-preview1` を受理、`EmitMode` とは独立。
- `NativeEmitter.configuredTargetMachine` の silent host fallback を hard error に（現状 wasm 要求が黙って Mach-O になる）。
- `CompilerBackend/Wasm/` 新設: `WasmModuleWriter`（セクション/LEB128/name section）、`WasmTypes`（valtype/reftype/struct/array）。この時点では writer 単体テストのみ（`wasm-tools validate` or 期待バイト列 golden）。
- `.kklib` manifest の `target` に wasm 文字列を許容。
- 診断コード空間 `KSWIFTK-WASM-*` を確保。
- Exit: `kswiftc --target wasm32-wasi --emit wasm-obj` が空モジュールを出力して validate を通る。

### M1 — 最小実行パイプライン（hello world）

- `WasmEmitter`（KIR → wasm func。KIR レジスタ→wasm local、分岐→block/loop/if、`call`→`call`）。
- 値表現 v1: Any = `eqref`、クラス = `(struct $typeInfo anyref fields...)`、String = `(array i16)` または `externref`（M3 で決定固定）、primitives = i32/i64/f64、boxing = struct wrapper、Unit = i32 定数。
- 例外: wasm EH を使わず、既存の outThrown プロトコルを wasm global/local 経由で移植（M2 まで最小）。
- WASI import 最小セット: `fd_write`（stdout）, `proc_exit`, `args_get/sizes_get`, `environ_*`, `clock_time_get`, `random_get`。
- `WasmLinkPhase`: wasm object 不要（モジュール直 emit）。entry = WASI `_start` + Kotlin main 呼出 + thrown チェック。
- `kswiftc --target wasm32-wasi hello.kt -o hello.wasm && wasmtime hello.wasm` で `println` 動作。
- テスト: `Tests/CompilerBackendTests/Wasm/` 新設 + `wasmtime` を使う fixture runner（実行環境なし環境では skip）。

### M2 — コア言語機能

- クラス/継承/vtable: GC struct の先頭フィールドに typeinfo（`= (struct itable-ref …)`）、virtual call = `call_indirect`（itable lookup は native の `kk_vtable_lookup` 相当を wasm 内関数として実装）。
- interface dispatch: itable を table + call_indirect、または upstream 方式（interface method → itable slot）。
- boxing/unboxing、`is`/`as`（`ref.test`/`ref.cast`）、`when`（subject 変換済み KIR）、range/for（Lowering 済み）、data/enum/sealed/object/companion、delegation、lateinit/lazy（これらは全て Lowering が処理 → emitter 側は「lowered KIR を正しく出す」だけ）。
- 例外本対応: outThrown チャネルの wasm 版を完成（nullable eqref 戻り or funcref table 経由の throw 値受け渡し設計）。
- `diff_kotlinc` wasm レーン: `DIFF_ENGINE=wasmtime`、`.expected` サイドカー方式を再利用し wasm-only ケースを `// DIFF_WASM_ONLY` のような directive で追加。言語系既存ケースを wasm でも実行。
- Exit: `Scripts/diff_cases` の言語機能系（標準 IO 非依存）の採用サブセットが wasmtime 緑。

### M3 — stdlib Kotlin 化 + kotlin.wasm 基礎

最大かつ最長のワークストリーム。並行して M2 と進められる。

- `Stdlib/wasm/` ソースセット新設 + `wasm/manifest.json`（jvm manifest の `commonSources`/`declarations`/`platform-operations.json` パターン踏襲）。
- `BundledStdlib` の `jvm/` 除外を `CompilationTarget` 駆動のソースセット選択に一般化。
- `kotlin/` 共通ソース内の platform 依存部を `internal expect` に抽出（string 内部表現、array primitive、io、random、time、platform reporting）し、`wasm/` に `actual`/`external` を配置。**既存ネイティブ側には同名 `actual`（= 現状実装）を維持してリグレッションを防ぐ**。
- kk_* 表面の段階移行: diff_cases 実行に必要な順で優先度付け（文字列操作 → 配列 → List/Set/Map → 数値変換 → println 周辺）。実装先は Kotlin 本体。エンジン提供機能（GC, ref.eq, array.new）以外の最小「wasm runtime 関数」（malloc 不要; JS interop helper 程度）だけ別途定義。
- `kotlin.wasm` パッケージ: `kotlin.wasm.WasmImport`/`WasmExport` 相当、`kotlin.wasm.unsafe.*`（`MemoryAllocator`, `Pointer`, `wasmMemorySize` 系 — linear memory interop 用）、`kotlin.wasm.internal.*`。
- `external` のユーザ解放: wasm ターゲット時は `KSWIFTK-SEMA-0008` を外し、`external` = wasm import にマップ。`@KsSymbolName` を拡張 or 新 `@KsWasmImport(module, name)` で import module 指定可能に。
- Exit: `println`, `listOf().map`, `String.format` 相当、例外 throw/catch が wasm で動き、diff_cases の stdlib 系サブセットが緑。

### M4 — 高度機能

- coroutine: CPS ステートマシンは Lowering 済みでそのまま動く。`runBlocking`/`delay`/dispatcher = 単一スレッドイベントループを Kotlin で実装（WASI: `poll_oneoff` 待機; wasmJs: M5 の JS イベントループ）。Channel/Flow の blocking 経路は要イベントループ化（現行の DispatchSemaphore 待機の代替）。
- リフレクション相当: `RuntimeReflectionMetadataEmitter` の wasm 版（typeinfo struct へのメタデータ埋込み or wasm data セグメント + `KClass` 問い合わせ）。
- `kotlin.system`（exitProcess, measureTimeMillis）、`kotlin.random`（random_get）、`kotlin.time`、`AtomicXxx`（単一スレッド = 素の load/store）、`DeepRecursive`（heap trampoline なのでそのまま）。
- Exit: kotlinx.coroutines 相当の bundled ソース（`runBlocking`, `launch`, `delay`, `flow`）が wasm で動作。

### M5 — wasmJs（JS interop 本体）

- `externref` 型を型系に導入: `JsAny`（=`externref` の opaque nominal）, `JsArray`, `JsString`, `JsNumber`, `JsBoolean`, `JsReference<T>`, `toJs*()`/`toKotlin()` 変換。
- `external` 宣言 → `(import "module" "name" (func ...))`: `@JsModule`, `@JsQualifier`, `@JsName`, `@JsNonModule` の意味論実装（アノテーションクラス自体は `kotlin/js` に既存 or 追加）。
- `@JsFun("...code...")` + `js("...")` intrinsic: JS コード片を glue に配置し wasm import として呼ぶ。
- `.mjs` glue 生成: imports オブジェクト構築、文字列変換 adapter（wasm string ↔ JS string は boundary でコピー — 上流方式）、`start`/`main` 呼出 export、exception → JS Error 変換。
- `@JsExport` → wasm export + JS 側エントリ。（Sema 検証は既存 `JsExportValidation` を wasm モードで活性化。）
- entry: `main()` を `main` export or glue から呼ぶ形（`_start` ではなく）。
- Exit: `console.log`, DOM 不要範囲の JS 呼出、`@JsExport` クラスが Node で動作、`node app.mjs` で実行。

### M6 — 相互運用拡張

- `kotlinx.coroutines` on JS: Promise 統合（`kotlinx-coroutines-core` の wasmJs dispatcher 相当）、`JsPromise`/`await`、JS setTimeout 駆動 delay。
- `JsArray`/`JsMap` 系 ↔ Kotlin コレクション変換（`kotlin.js` wrapper は既存。view 系メンバーは wasmJs では external/view 実装に差し替え余地）。
- `.d.ts` 生成（export 対象の TS 宣言）。
- ブラウザ DOM API 用の typed facade は対象外（ユーザが `external` で書ける状態まで）。
- sourcemap / DWARF はスコープ外（name section のみ）。

### M7 — ライブラリ・ツール・CI

- `.kklib` wasm: objects[] = wasm object（wasm-ld 形式 or 自前 relocatable — 決定要）or wasm では inline-kir + metadata のみで object 遅延 emit も選択肢（再現性・速度の観点で有利）。
- Incremental compilation の fingerprint に target を含める（`IncrementalCompilationCache`）。
- LSP: 新診断の対応程度（本体は無改修で動く想定）。
- CI: `nightly-full.yml` に wasm レーン（wasmtime + node の setup action、`diff_cases` wasm サブセット、wasm fixture suite）。PR ゲートには入れない（長時間化回避 — まず nightly）。
- `Scripts/diff_kotlinc.sh` の wasm レーン: `DIFF_ENGINE=wasmtime|node`、case directive `DIFF_WASM_ONLY` / `DIFF_WASM_SKIP`。
- docs: spec.md に wasm emit/target 仕様、ARCHITECTURE.md に `CompilerBackend/Wasm/` 追加。

## 3. 横断タスク一覧（フェーズ非依存）

| # | タスク | 依存 |
|---|---|---|
| T1 | `CompilationTarget` 導入 + 全 gating 箇所の置換（`isJVM`, `TargetTriple` 参照） | M0 |
| T2 | silent host fallback を診断化 | M0 |
| T3 | wasm binary writer（types/imports/funcs/tables/elems/memory/globals/exports/code/data/tags/name）+ golden byte test | M0→M5 で拡張 |
| T4 | WasmEmitter: KIR→wasm（locals, block/if/loop/br, call/call_indirect/call_ref, ref.test/cast, struct/array ops） | M1→M4 で拡張 |
| T5 | outThrown プロトコルの wasm 版 | M1（最小）/M2（完成） |
| T6 | `Stdlib/wasm/` + `internal expect` リファクタ（kotlin/ 共通層からの platform 依存分離） | M3 |
| T7 | kk_* → Kotlin 実装移行（優先度順、native 側保持） | M3〜M6 |
| T8 | `external` ユーザ解放 + import module/name 機構 | M3（WASI import）/M5（JS import） |
| T9 | 単一スレッドイベントループ（WASI poll_oneoff / JS） | M4 |
| T10 | `.mjs` glue generator | M5 |
| T11 | diff/CI レーン（wasmtime, node） | M2 以降継続 |

## 4. リスクと未決事項

| リスク | 影響 | 緩和 |
|---|---|---|
| kk_* Kotlin 化の規模（~2,000 関数） | 最大コスト | diff_cases 駆動の優先度付け。実装が Kotlin で共有される分、native 側へ逆輸入して二重実装を解消する選択肢も残る |
| String 表現（array i16 vs externref） | stdlib 全体と JS boundary コストに波及 | 上流同様「内部は array、boundary で JS 変換」が無難。M1 で暫定決め、M3 で確定 |
| WasmGC 対応状況 | Node 22+/Chrome/Firefox/wasmtime は OK、古い環境不可 | 問題なしと判断（CI で toolchain 固定） |
| wasm EH | 提案実装がエンジンでばらつき | outThrown 継続で回避、wasm EH は後続最適化 |
| virtual dispatch | itable をどこに持つか | upstream は struct フィールド + call_indirect。最初は素朴な型ID→func table |
| `external` 解放のセキュリティ/安全性 | SEMA-0008 の意味を変える | ターゲット wasm のときだけ許可し診断コードは維持 |
| `.klib`（Kotlin/Native）相互運用 | 上流 wasm .klib は別 IR | 対象外（KSwiftK .kklib で wasm を配布） |
| ランタイムの機能差 | JDBC/SQLite/ネットワーク/cinterop は wasm 非対応 | `RuntimeABISpec` に capability/tier 注記、利用時に `KSWIFTK-WASM-*` 診断 |
| jscpd/行数規律 | 新規大量コード | writer/emitter は責務分割命名規約に従う |

## 5. 成功指標

- `Scripts/diff_cases` の言語系 + stdlib 系で wasm 実行がネイティブと同 stdout（kotlinc 参照が立てられないので `.expected` 駆動 + native 実行との 2 軸比較）。
- `Tests/CompilerBackendTests/Fixtures` に wasm 実行モード（engine 不在は skip）。
- `kotlinx-coroutines` bundled テスト相当が wasm で通る。
- Hello/collections/coroutines の wasm artifact サイズを計測し docs に記録（baseline として）。

# Kotlin/Wasm フルサポート メガプラン

> ステータス: M0/M1/M2（linear-memory MVP 範囲）を実装済み。M3 は `kotlin.wasm` 宣言層 + コレクション基盤（List/Set/Map 系）まで実装済み（後述「実装ステータス」節参照）。残りは引き続き計画段階。
> 対象読者: KSwiftK に wasm ターゲットを追加する作業者向けの総合ロードマップ。

## 実装ステータス（2026-10 時点）

**済み（M0 + 縮小版 M1 + linear-memory 版 M2）**:

- `TargetTriple` に `wasmWASI`（`wasm32-unknown-wasi`）/ `wasmJS`（`wasm32-unknown-js`）と `isWasm` / `isWASI` / `isWasmJS` を追加（`CompilerTypes.swift`）。`--target wasm32-wasi` 等の 2 セクション綴りを受理し canonical 化（`CLIParser.swift`）。未対応ターゲットの silent host fallback を廃止し診断化。
- `CompilerBackend/Wasm/` に自前の wasm バイナリエンコーダ＋エミッタを新設: `WasmModule.swift`（LEB128、type/import/func/table/memory/global/export/elem/code/data/name 各セクション）、`WasmEmitter.swift`（モジュールパス、関数/helper/stub index 管理、`_start` 生成）、`WasmEmitter+Function.swift`（KIR → 構造化制御フロー lowering）、`WasmEmitter+Runtime.swift`（ランタイム helper / builtin op テーブル）。
- `CodegenPhase` が wasm ターゲット時に `WasmEmitter` へ分岐し `.wasm` を `CompilationContext` に格納。`LinkPhase` は wasm 出力をネイティブリンク対象から除外。
- WASI MVP が Node `node:wasi` 上で実行可能: `_start` + `proc_exit`、`fd_write` による `print`/`println`（bundled stdlib の `kotlin.io.println`/`print` は raw WASI helper にルーティング）。整数四則・比較・分岐・while/for ループ・再帰・直接呼出・文字列リテラル出力が動作。
- **M2（linear-memory 版）**:
  - オブジェクト: `kk_object_new(layoutWords, typeID)` がヘッダ `{typeID@-16, layoutWords@-8}` + slot 配列（slot0=iface map, slot1=vtable ptr, slot2+=フィールド）を bump-allocate。フィールド get/set はネイティブと同じ `kk_array_get_inbounds`/`kk_array_set`（in-bounds は meta バウンズチェック付き）。
  - 仮想呼出: `virtualCall` は `call_indirect`。vtable は object slot1 の遅延割当てメモリ（direct 16 + itable 32×16 entry）、`kk_object_register_vtable_method` が table slot index を書き込む。itable は `kk_object_register_itable_method`/`_iface` + `__kk_wasm_itable_lookup`（動的 iface 探索）。
  - `is`/`as`: `kk_op_is`/`kk_op_cast`。nominal 判定は `obj.typeID` を `$__kk_wasm_is_assignable`（`kk_type_register_super`/`_iface` のエッジリスト推移閉包）で検査。トークン形式は native `RuntimeTypeTokenEncoding`（base=token&0xFF, nullable=0x100, payload=token>>9）を踏襲。
  - 例外: outThrown プロトコル（`thrown` wasm global）を踏襲。`canThrow` 呼出後に thrown を `thrownResult` ローカルへ移しクリア（`emitThrownCheck`）、`jumpIfNotNull` が catch へ分岐、未捕捉は `_start` が `proc_exit(70)` に変換。`.rethrow` は thrown に書き `return 0`。
  - Throwable  intrinsic: `__kk_exception_new*` 系（`@KsSymbolName` ctor）は wasm helper で real box を生成 — typeID は fqName の FNV-1a（`runtimeStableNominalTypeID` 同等、55bit mask）、ctor 内で `kotlin.*`/`kotlinx.*` の throwable 継承エッジを `kk_type_register_super` で登録するため `catch (e: Throwable)`/`RuntimeException` 等の supertype match が効く。`message`/`cause` slot 経由で `e.message` も動作（vtable[2]/[3] に accessor helper を登録）。
  - Throwable 表示/終了処理: `toString` は `fqName` / `fqName: message` 形式（vtable[1] に登録）、`getStackTrace` は空配列（vtable[0]）、未捕捉例外は `_start` が `Uncaught Kotlin exception: <toString>` を **stderr（fd=2）** に出力して `proc_exit(70)`。`initCause`/`cause`・`addSuppressed`/`suppressed`（meta を論理 count とする容量 8 の配列）も動作。
  - 配列 intrinsic: `kk_array_of`（vararg パック済み配列の identity）、`kk_empty_array`、`kk_array_of_nulls`（負長で thrown）、`kk_array_is_empty`、`__kk_array_size`/`__kk_*Array_size` 系（全て meta 読み）。`intArrayOf(7,8,9)[1]` → `8`、`a.size` → `3` を実機確認。
  - accessor ルーティング: `call get`/`call set` の synthetic accessor シンボルを `propertySymbol(forAccessor:)`/`accessorOwnerProperty(for:)` でプロパティへデコードし fqName マッチ（`kotlin.collections.size` → `__kk_array_size`、`kotlin.Throwable.suppressed` → `__kk_throwable_suppressedRaw` 等）。runtime helper のキーは `name/arity`。
  - 実 Kotlin プローブで検証済み: クラス生成+フィールド（`hi bob`）、override 仮想 dispatch（`2`/`1`）、`is`/`as`（`1`/`1`）、try/catch/finally（`caught`/`after`）、`e.message`（`bang`）、`e.cause`、複合 interface、`toString`（`kotlin.Exception: bang`）、未捕捉 stderr 出力+exit 70、suppressed×2。
- **M3 着手**: `Stdlib/wasm/kotlin/wasm/` に `kotlin.wasm` API の宣言層を新設（`@JsFun`/`@JsModule`/`@JsQualifier`/`@ExperimentalWasmJsInterop`、`JsAny`/`JsReference`/`JsArray`/`JsFunction`/`JsError`/プリミティブ wrapper、`js(code)`、`kotlin.wasm.unsafe` の `Pointer`/`MemoryAllocator`/`withMemoryScoped`）。`external` class/interface はフロントエンド未対応のため plain marker 宣言。`BundledStdlib.collectBundledStdlibSources` は `wasm/` ツリーを wasm ターゲット時のみ注入（`FrontendPhases` が `ctx.options.target.isWasm` で切替。`jvm/` は従来どおり常時除外）。
- **M3（コレクション基盤）**: List 系を linear-memory オブジェクト箱 `{slot2=backing array, slot3=count, slot4=flags(bit0=readOnly)}` で実装。`__kk_list_of`/`__kk_array_list_of`/`__kk_emptyList`（`kk_object_new(5)` で生成、slot0/1 はオブジェクトメタ予約）、`__kk_mutable_list_add`（readOnly 検査→満杯時は `max(8, cap*2)` で backing を再確保してコピー、boxed Boolean `1` を返す）、`__kk_list_size`/`__kk_list_get`（範囲外は thrown）、`__kk_list_check_modification`（現状 no-op）、`kk_list_iterator`/`_hasNext`/`_next`（slot2=list, slot3=index, slot4=CME センチネル）、`__kk_list_to_list`（`toList` — 配列コピー+readOnly 箱）を wasm helper として実装。`kotlin.collections.toList`/`suppressedExceptions`（生配列を readOnly List 箱でラップ）/`kotlin.collections.<List|MutableList|ArrayList|…>.size` の accessor→helper ルーティングも追加。`mutableListOf`+`add`+`size`+添字+for 走査+`toList` を実プローブで検証（`4`/`2`/`1,2,3,4`/`2`）、`e.suppressedExceptions.size`=2 + `for s in … println(s.message)` で `s1`/`s2` を実機確認。
- **M3（Set/Map 基盤）**: Set は List 箱レイアウトを共有（`__kk_set_of`/`__kk_linked_hash_set_of`/`__kk_emptySet`/`__kk_mutable_set_add|remove|clear`/`__kk_set_size|contains|is_empty`、`__kk_set_freeze`=identity）。重複排除は `__kk_wasm_elem_eq`（raw i64 一致または両辺 String 時の構造的バイト比較）で判定。Map は `{keys array, values array, count, flags}` の並列配列箱（`__kk_map_of`/`__kk_linked_hash_map_of`/`__kk_emptyMap`、pairs 系は `__kk_map_of_pairs` 等で Pair 箱を展開、`__kk_map_size|get|contains_key|contains_value|keys|values|entries`、`__kk_mutable_map_put|remove|clear`、`__kk_map_freeze`、内部 `__kk_wasm_map_index_of`）。Pair/Entry は `{first, second, mapRef, mapKey}` 箱（`kk_object_new(6)`、slot5 まで確保）で、`mapRef != 0` の live entry は `value`/`setValue` が `map[mapKey]` をライブ解決。List/Set 箱は Iterable/Sequence/MutableIterable/Collection/Set の itable、Map 箱は Map/MutableMap の itable（メソッド+プロパティ getter スロット）、Entry/イテレータ箱は Map.Entry/MutableEntry/Iterator の itable を登録。`kk_iterator_hasNext`/`_next` は純粋な itable 委譲（ソース実装の匿名 Iterator オブジェクトも正しく dispatch）。`itableDynamic` の lookup ミスは table[0] 誤呼出ではなく `unreachable` にトラップ（native の `kk_dispatch_error` 相当）。`__kk_string_equals_flat` は構造的バイト比較を実装済み（`e.key == "b"` 等が実動）。実プローブで `mutableMapOf`+`containsKey`/`containsValue`+`keys`/`values`/`entries` 走査+`entry.setValue` ライブ書込+`remove`+readOnly `mapOf`/`setOf` dedup+`for`分割代入+`in`+Pair `first`/`second` を Node WASI で検証済み。
- **M3（プリミティブ文字列化パリティ）**: `println(true)` が `1` と出力されていた問題を修正 — `ConsolePrintLoweringPass` がプリミティブ引数の `kk_any_to_string` tag を `1` 固定にしていたのを、Boolean→`2`/Char→`4` に分岐。wasm 側の `emitAnyToStringBody` は tag=2→`"true"/"false"`、tag=4→UTF-16 コードユニットの UTF-8 エンコード（1〜3バイト）を実装。native/wasm 両ターゲットで `true/false`・Char 出力が一致。
- **M3（accessor ルーティング補完）**: `Pair.second`/`component2`（および `first`/`component1`）の accessor→helper ルートを追加 — bundled `Pair` は `first` プロパティにのみ `@KsSymbolName` を持ち、`second` はソース getter 経由だったため `call get` が stub→0 を返していた。
- 未実装ランタイム callee はゼロ返し stub を生成し、件数＋名前を warning で報告（~140 件。診断される限り silent な誤動作ではない）。
- テスト: `Tests/CompilerBackendTests/Codegen/WasmCodegenTests.swift`（12 件。モジュール構造・制御フロー・stub 診断・Node WASI 実行: hello/オブジェクト+is/仮想 dispatch/try-catch/配列 intrinsic/未捕捉例外 stderr+exit 70/リスト intrinsic＋イテレータ/Map+Set intrinsic＋generic イテレータ dispatch）。

**計画からの意図的な偏差**: 現実装は計画案 B（WasmGC）ではなく **linear-memory + 全値 i64** 表現。理由は「エミッタ/ドライバ配管と KIR→wasm 制御フロー lowering、及びオブジェクト/例外モデルを先に実証し、WasmGC へは後続で移行する」段階戦略。boxing は現状 identity。

**残制限（M3 以降の作業）**: 全値 i64 表現のまま（tagged スキーム未導入）、generic 消去済みフィールドのみ、stacktrace は空配列（実フレーム捕捉なし、`stackTraceToString` は stub）、`kk_throwable_is_cancellation` は typeID 一致のみ、Map/Set の等価判定は raw i64＋String 構造比較のみ（任意オブジェクトの `equals` は未呼出 — 同値の別 String は一致するがカスタム `equals`/`hashCode` は未対応）、Float/Double 等の浮動小数 tag（5/6）の文字列化は未実装、`__kk_list_check_modification` は no-op（subList ビュー無効化機構が前提）、イテレータの CME センチネルは fail-fast だが診断なし、`kk_indexing_iterable_*`/range イテレータ系は未実装（`for (x in array)`/`for (i in 1..n)` 経路は未検証）、callee 名一致で `.direct` 解決された accessor は一部 fqName マッチ経由のためカバレッジは漸進的。文字列操作の残り・数値変換・`joinToString` 等の上位 stdlib 関数は未着手。

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

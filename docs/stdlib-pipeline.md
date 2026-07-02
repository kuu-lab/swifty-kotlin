# Stdlib source pipeline and synthetic stub inventory

Status: 2026-07-02.

This note is the RF2/RF3 coordination document for moving stdlib declarations out
of synthetic Sema stubs and into bundled Kotlin source where possible.

Current synthetic-stub footprint in this checkout:

- `HeaderHelpers+Synthetic*.swift`: 121 files
- total line count: 82,606 lines
- central dispatch: `registerSyntheticDelegateStubs` plus the
  `registerSyntheticPhase_ExtendedStdlib` batch

## Pipeline rules

`LoadSourcesPhase` currently injects bundled stdlib sources before user inputs:

1. It enumerates `Bundle.module/Stdlib` from `Sources/CompilerCore/Stdlib`.
2. It adds each `.kt` file as a synthetic `__bundled_...` source path, except
   entries in `excludedBundledStdlibFiles`.
3. It then adds residual string-backed sources from `BundledKotlinStdlib`.
4. User input files are added after bundled sources.

RF-STDLIB-003 is the next important correctness gate for broad stub removal:
source declarations must win over equivalent synthetic stubs, and duplicate
source/stub declarations should produce a stable diagnostic before deleting a
large (b) stub block.

## Bucket key

| Bucket | Meaning | Action |
|---|---|---|
| (a) cleanup | JS/Wasm/JVM/JDK-only or otherwise target-out compatibility surface | Delete through `CLEANUP-STUB-*`; do not refactor except to isolate deletion seams. |
| (b) source migration | Public stdlib surface that belongs in M1-M17 bundled Kotlin source | Keep until the matching `.kt` declaration is wired, then remove stub, direct runtime ABI, tests, and golden entries together. |
| (c) residual compiler surface | True compiler scaffolding or platform-native support that should remain synthetic for now | Convert hand-written registration to declarative tables via RF-STUB-003/004/006. |

Mixed files are assigned to the bucket that owns most of the file today. The
notes column calls out sub-blocks that should be split before the final delete or
table migration.

## RF-STUB-002 reference cleanup recipe

`CLEANUP-STUB-033/034` already removed the old PlatformAndJS phase file and the
JS/Wasm/JVM calls that were in `SyntheticPhase_ExtendedStdlib`. The remaining
(a) work should follow the same shape:

1. Remove the registration call from `registerSyntheticDelegateStubs` or the
   relevant phase batch.
2. Delete the stub file, or split the file first if only some declarations are
   target-out.
3. Delete matching `RuntimeABISpec` entries and runtime `@_cdecl` implementations
   that are no longer emitted.
4. Delete Swift tests and `.golden` expectations that only prove the removed
   target-out surface.
5. Run focused Sema/runtime tests for the touched surface, then run golden
   regeneration only for affected cases.
6. Update `docs/stdlib-fiction-audit.md` with the new synthetic symbol count
   when a phase-sized cleanup lands.

## Synthetic stub inventory

| File | Lines | Bucket | Owner / next action |
|---|---:|:---:|---|
| `HeaderHelpers+SyntheticArrayStubs.swift` | 2043 | (c) | Array and primitive-array compiler surface; split source-backed factories/HOF later. |
| `HeaderHelpers+SyntheticAtomicStubs.swift` | 2512 | (b) | `AtomicMigration.kt` owner; split Java atomic interop cleanup pockets first. |
| `HeaderHelpers+SyntheticBase64Stubs.swift` | 830 | (b) | MIGRATION-ENC owner; Kotlin source exists but public stubs still dispatch directly. |
| `HeaderHelpers+SyntheticBigIntegerStubs.swift` | 620 | (a) | `java.math.BigInteger` compatibility; target-out cleanup candidate. |
| `HeaderHelpers+SyntheticBuilderDSLStubs.swift` | 414 | (b) | M3 collection builder source migration. |
| `HeaderHelpers+SyntheticCInteropStubs.swift` | 3065 | (c) | Kotlin/Native interop compiler/runtime surface; table-driven residual candidate. |
| `HeaderHelpers+SyntheticCharStubs.swift` | 987 | (c) | Primitive `Char` shell plus helpers; keep as built-in until a dedicated source split exists. |
| `HeaderHelpers+SyntheticClockStubs.swift` | 451 | (b) | M8 time source migration. |
| `HeaderHelpers+SyntheticCloseableStubs.swift` | 277 | (b) | `Closeable`/`use` common surface; move to Kotlin source before deleting. |
| `HeaderHelpers+SyntheticCoercionStubs.swift` | 1349 | (b) | M6 range/coercion source migration; many overloads already source-backed. |
| `HeaderHelpers+SyntheticCollectionTypeAliases.swift` | 272 | (b) | M3 collection typealias/source migration. |
| `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift` | 631 | (b) | Core collection/comparable shells; source migration owner, with residual type hooks. |
| `HeaderHelpers+SyntheticComparableHelpers.swift` | 168 | (c) | Helper-only file for residual comparable registration. |
| `HeaderHelpers+SyntheticComparatorStubs.swift` | 1446 | (b) | M5 comparisons/comparator source migration. |
| `HeaderHelpers+SyntheticComparisonStubs.swift` | 1083 | (b) | M5 `maxOf`/`minOf` and comparison helpers. |
| `HeaderHelpers+SyntheticConcurrencyStubs.swift` | 186 | (a) | `java.lang.Thread` / JVM-style `kotlin.concurrent.thread`; cleanup candidate. |
| `HeaderHelpers+SyntheticCoroutineHelpers.swift` | 763 | (c) | Suspend/coroutine compiler/runtime scaffolding; consolidate with coroutine registry. |
| `HeaderHelpers+SyntheticCoroutineStubs.swift` | 2422 | (c) | `kotlin.coroutines` and supported coroutine runtime surface. |
| `HeaderHelpers+SyntheticCoroutinesStubs.swift` | 365 | (c) | ABI-facing coroutine support; RF-STUB-005 naming consolidation. |
| `HeaderHelpers+SyntheticDeepRecursiveStubs.swift` | 324 | (b) | Public stdlib surface; source migration before removal. |
| `HeaderHelpers+SyntheticDurationStubs.swift` | 1390 | (b) | M8 duration source migration; bridge-only `__kk_*` declarations may remain private. |
| `HeaderHelpers+SyntheticDynamicStubs.swift` | 101 | (a) | Kotlin/JS `dynamic`; cleanup candidate. |
| `HeaderHelpers+SyntheticEnumStubs.swift` | 474 | (c) | Enum compiler surface. |
| `HeaderHelpers+SyntheticExceptionStubs.swift` | 907 | (c) | Core exception shells required by diagnostics/lowering; declarative residual candidate. |
| `HeaderHelpers+SyntheticExperimentalBitwiseStubs.swift` | 99 | (b) | Experimental bitwise stdlib helpers; source migration owner. |
| `HeaderHelpers+SyntheticExperimentalMarkerStubs.swift` | 367 | (c) | Common opt-in markers stay; split JS/Wasm markers into (a) cleanup first. |
| `HeaderHelpers+SyntheticExperimentalTimeStubs.swift` | 828 | (b) | M8 experimental time source migration. |
| `HeaderHelpers+SyntheticFileIOStubs.swift` | 2532 | (a) | `java.io.File` / JVM I/O compatibility dominates; split private source bridges if retained. |
| `HeaderHelpers+SyntheticFileTreeWalkStubs.swift` | 291 | (a) | JVM file-walk compatibility; cleanup candidate. |
| `HeaderHelpers+SyntheticFileWalkDirectionStubs.swift` | 113 | (a) | JVM file-walk support enum; cleanup with file-walk surface. |
| `HeaderHelpers+SyntheticFilesUtilityStubs.swift` | 520 | (a) | `java.nio.file` / files utility surface; target-out cleanup. |
| `HeaderHelpers+SyntheticFunctionTypeStubs.swift` | 523 | (c) | Function interfaces are compiler-known. |
| `HeaderHelpers+SyntheticGroupingStubs.swift` | 373 | (b) | M3 grouping/HOF source migration. |
| `HeaderHelpers+SyntheticHexFormatStubs.swift` | 589 | (b) | MIGRATION-ENC owner; source exists but not fully wired. |
| `HeaderHelpers+SyntheticInstantStubs.swift` | 441 | (b) | M8 time source migration. |
| `HeaderHelpers+SyntheticIterableMembers.swift` | 1497 | (b) | M3 collection HOF/member source migration; RF-STUB-005 naming cleanup after bucket split. |
| `HeaderHelpers+SyntheticIterableStubs.swift` | 1326 | (b) | M3 iterable/collection shells and members. |
| `HeaderHelpers+SyntheticIteratorStubs.swift` | 310 | (c) | Iterator and primitive iterator compiler surface. |
| `HeaderHelpers+SyntheticJsAnyStubs.swift` | 25 | (a) | Kotlin/JS surface; cleanup candidate. |
| `HeaderHelpers+SyntheticJsArrayExternalClassStubs.swift` | 80 | (a) | Kotlin/JS surface; cleanup candidate. |
| `HeaderHelpers+SyntheticJsArrayStubs.swift` | 71 | (a) | Kotlin/JS surface; cleanup candidate. |
| `HeaderHelpers+SyntheticJsFunctionStubs.swift` | 77 | (a) | Kotlin/JS `js(...)`; cleanup candidate. |
| `HeaderHelpers+SyntheticJsNumberStubs.swift` | 117 | (a) | Kotlin/JS number bridge; cleanup candidate. |
| `HeaderHelpers+SyntheticJsStringInteropStubs.swift` | 183 | (a) | Kotlin/JS string interop; cleanup candidate. |
| `HeaderHelpers+SyntheticKotlinAnnotationStubs.swift` | 790 | (c) | Core annotation and opt-in metadata surface. |
| `HeaderHelpers+SyntheticKotlinIOExceptionStubs.swift` | 133 | (b) | `kotlin.io` exception shell; source/runtime migration owner. |
| `HeaderHelpers+SyntheticKotlinVersionStubs.swift` | 372 | (b) | Public stdlib value surface; source migration owner. |
| `HeaderHelpers+SyntheticListAggregateMembers.swift` | 1288 | (b) | M3 list aggregate/source migration. |
| `HeaderHelpers+SyntheticListConversionMembers.swift` | 434 | (b) | M3 list conversion/source migration. |
| `HeaderHelpers+SyntheticListIndexedAndArrayDequeStubs.swift` | 690 | (b) | M3 `IndexedValue` / `ArrayDeque` source migration. |
| `HeaderHelpers+SyntheticListStubs.swift` | 1967 | (b) | M3 list shell and member migration. |
| `HeaderHelpers+SyntheticListTransformMembers.swift` | 797 | (b) | M3 list transform/source migration. |
| `HeaderHelpers+SyntheticLocaleConstructorStubs.swift` | 401 | (a) | `java.util.Locale`/locale interop; cleanup candidate unless retained behind private bridge. |
| `HeaderHelpers+SyntheticMapStubs.swift` | 1255 | (b) | M3 map shell and HOF source migration. |
| `HeaderHelpers+SyntheticMathStubs.swift` | 953 | (b) | Math stdlib source migration, with numeric primitive hooks. |
| `HeaderHelpers+SyntheticMetadataAnnotations.swift` | 15 | (c) | Metadata helper surface. |
| `HeaderHelpers+SyntheticMetaprogAnnotationHelpers.swift` | 953 | (c) | Annotation infrastructure; split JVM-only annotations into (a) before table migration. |
| `HeaderHelpers+SyntheticMutableCollectionArrayAddAll.swift` | 109 | (b) | M3 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableCollectionIterableAddAll.swift` | 104 | (b) | M3 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableCollectionSequenceAddAll.swift` | 101 | (b) | M3/M4 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableListStubs.swift` | 1549 | (b) | M3 mutable list shell and member migration. |
| `HeaderHelpers+SyntheticNativeConcurrentAtomicLazy.swift` | 96 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentAtomicReference.swift` | 152 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentCommon.swift` | 737 | (c) | RF-STUB-004 NativeConcurrent shared table body. |
| `HeaderHelpers+SyntheticNativeConcurrentContinuation.swift` | 297 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentDetachedObjectGraph.swift` | 190 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentEnsureNeverFrozen.swift` | 54 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentExceptions.swift` | 128 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentFreezableAtomicReference.swift` | 136 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentFreeze.swift` | 156 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentFuture.swift` | 106 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentLegacyAtomicScalars.swift` | 360 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentMutableData.swift` | 218 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` | 312 | (c) | RF-STUB-004 NativeConcurrent entry point. |
| `HeaderHelpers+SyntheticNativeConcurrentWaitForMultipleFutures.swift` | 96 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentWaitWorkerTermination.swift` | 37 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentWithWorker.swift` | 69 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentWorker.swift` | 172 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeConcurrentWorkerBoundReference.swift` | 106 | (c) | RF-STUB-004 NativeConcurrent table consolidation. |
| `HeaderHelpers+SyntheticNativeDataStubs.swift` | 821 | (c) | Native data/runtime support; declarative residual candidate. |
| `HeaderHelpers+SyntheticNativeFunctionAnnotationStubs.swift` | 85 | (a) | `kotlin.js.nativeGetter/nativeSetter/nativeInvoke`; cleanup candidate. |
| `HeaderHelpers+SyntheticNativeInteropHelpers.swift` | 1292 | (c) | Kotlin/Native interop helper surface; table-driven residual candidate. |
| `HeaderHelpers+SyntheticNativeInteropStubs.swift` | 386 | (c) | Kotlin/Native interop annotations/types. |
| `HeaderHelpers+SyntheticNativeRefRuntimeStubs.swift` | 1135 | (c) | Native ref runtime support; declarative residual candidate. |
| `HeaderHelpers+SyntheticOnErrorActionStubs.swift` | 120 | (a) | File-tree walk support; cleanup with file-walk surface. |
| `HeaderHelpers+SyntheticPairTripleStubs.swift` | 409 | (b) | Public `Pair`/`Triple` source migration candidate. |
| `HeaderHelpers+SyntheticPathStubs+GenericFunctionRegistration.swift` | 548 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup with path surface. |
| `HeaderHelpers+SyntheticPathStubs+SymbolRegistration.swift` | 488 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup with path surface. |
| `HeaderHelpers+SyntheticPathStubs+TypeCreation.swift` | 337 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup with path surface. |
| `HeaderHelpers+SyntheticPathStubs.swift` | 2102 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup candidate. |
| `HeaderHelpers+SyntheticPhase_ExtendedStdlib.swift` | 56 | (c) | Temporary registry artifact; RF-STUB-006 will replace it with bucketed registries. |
| `HeaderHelpers+SyntheticPlatformObjectHelpers.swift` | 216 | (a) | Java class/platform object helpers; cleanup unless needed by residual annotations. |
| `HeaderHelpers+SyntheticPlatformTimeConversionStubs.swift` | 261 | (a) | JVM/JS platform time conversion; cleanup candidate. |
| `HeaderHelpers+SyntheticPreconditionStubs.swift` | 205 | (b) | `check`/`require`/`error` source migration. |
| `HeaderHelpers+SyntheticPropertyDelegateStubs.swift` | 2564 | (c) | Delegation and reflection scaffolding; declarative residual candidate. |
| `HeaderHelpers+SyntheticRandomStubs.swift` | 1147 | (b) | M7 random source migration; split Java random interop pockets into (a). |
| `HeaderHelpers+SyntheticRangeInterfaceStubs.swift` | 382 | (b) | M6 range interfaces/source migration. |
| `HeaderHelpers+SyntheticRangeProgressionStubs.swift` | 1116 | (b) | M6 range/progression source migration. |
| `HeaderHelpers+SyntheticRangeUntilStubs.swift` | 142 | (b) | M6 `..<`/`rangeUntil` source migration. |
| `HeaderHelpers+SyntheticReadWriteLockStubs.swift` | 216 | (a) | JVM-style lock compatibility; cleanup or move behind explicit platform bridge. |
| `HeaderHelpers+SyntheticRegexStubs.swift` | 974 | (b) | Regex public stdlib source migration candidate. |
| `HeaderHelpers+SyntheticResultStubs.swift` | 584 | (b) | M13 `Result` source migration; source exists. |
| `HeaderHelpers+SyntheticScopeFunctionStubs.swift` | 874 | (b) | Scope functions and `takeIf`/`takeUnless` source migration. |
| `HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift` | 1463 | (b) | M4 sequence registration helper surface. |
| `HeaderHelpers+SyntheticSequenceTerminalStubs.swift` | 3452 | (b) | M4 sequence terminal/HOF source migration. |
| `HeaderHelpers+SyntheticSerializationStubs.swift` | 850 | (a) | `kotlinx.serialization` compatibility; target-out cleanup unless retained as explicit library support. |
| `HeaderHelpers+SyntheticSetStubs.swift` | 1068 | (b) | M3 set shell and HOF source migration. |
| `HeaderHelpers+SyntheticStdlibLoopStubs.swift` | 88 | (b) | `repeat` source migration. |
| `HeaderHelpers+SyntheticStringBuilderStubs.swift` | 629 | (b) | M2 StringBuilder source migration; source exists. |
| `HeaderHelpers+SyntheticStringRegistrationHelpers.swift` | 475 | (b) | M1 string helper registration. |
| `HeaderHelpers+SyntheticStringStubs.swift` | 4180 | (b) | M1 string source migration; bridge-only `__kk_*` declarations may remain private. |
| `HeaderHelpers+SyntheticStringTypeHelpers.swift` | 299 | (c) | String type scaffolding and helper utilities. |
| `HeaderHelpers+SyntheticTODOAndIOStubs.swift` | 1347 | (b) | Mixed TODO, IO, system, duration, collection factories; split JVM/system pockets before broad M migration. |
| `HeaderHelpers+SyntheticTestStubs.swift` | 178 | (a) | `kotlin.test` test-only compatibility; cleanup outside production stdlib. |
| `HeaderHelpers+SyntheticThreadLocalStubs.swift` | 215 | (c) | Native/thread-local annotation support. |
| `HeaderHelpers+SyntheticTypedRangeStubs.swift` | 1090 | (b) | M6 typed range source migration. |
| `HeaderHelpers+SyntheticURIStubs.swift` | 178 | (a) | `java.net.URI`; cleanup candidate. |
| `HeaderHelpers+SyntheticURLStubs.swift` | 332 | (a) | `java.net.URL`; cleanup candidate. |
| `HeaderHelpers+SyntheticUnsignedRangeStubs.swift` | 561 | (b) | M6 unsigned range source migration. |
| `HeaderHelpers+SyntheticUuidStubs.swift` | 888 | (b) | M12 UUID source migration; source exists. |
| `HeaderHelpers+SyntheticW3CDomStubs.swift` | 78 | (a) | Kotlin/JS DOM surface; cleanup candidate. |

## Follow-up order

1. Finish small (a) deletions that still have direct central calls:
   `SyntheticJsAnyStubs`, `SyntheticJsFunctionStubs`, `SyntheticJsNumberStubs`.
2. Split mixed files before touching their residual parts:
   `SyntheticExperimentalMarkerStubs`, `SyntheticMetaprogAnnotationHelpers`,
   `SyntheticRandomStubs`, `SyntheticTODOAndIOStubs`, `SyntheticAtomicStubs`.
3. After RF-STDLIB-003, migrate one narrow (b) slice end-to-end and use it as the
   template for the remaining M1-M17 rows.
4. Start RF-STUB-003/004 only on files classified (c); do not table-drive code
   that is already scheduled for deletion or Kotlin source migration.

## Source pipeline design

### 目的

KSwiftK の stdlib 実装は、合成スタブと Runtime `kk_*` 直接呼び出しから、`Sources/CompilerCore/Stdlib` 配下の Kotlin ソースを通常のフロントエンド入力として扱う形へ段階移行する。

この設計メモは RF-STDLIB-001 のレビュー対象であり、実装 PR の前に次の境界を固定する。

- bundled `.kt` の読み込み順序と source origin
- stdlib ソース宣言と合成スタブの優先順位
- インクリメンタルキャッシュと golden 出力への影響
- 常時 stdlib コンパイルの時間コストを抑える戦略

### 現状

`Package.swift` は `CompilerCore` の resource として `Sources/CompilerCore/Stdlib` をコピーしている。現 HEAD の `LoadSourcesPhase` は `Bundle.module.resourcePath/Stdlib` を列挙し、ソート済みの `.kt` を `SourceManager` に `__bundled_...` virtual path として登録してからユーザー入力を読む。未移行 API は `BundledKotlinStdlib` の residual source でも注入される。

このため、RF-STDLIB-002 の基本配線はすでに入り始めている。一方で、以下はまだ設計上の固定が必要。

- `--no-stdlib` / `-Xfrontend no-default-stdlib-sources` 相当の opt-out が bundled source 注入に効くか
- `SourceManager` 上でユーザー入力と bundled stdlib source を origin として区別できるか
- stdlib ソース宣言が存在する場合に同シグネチャの synthetic stub 登録を確実に skip できるか
- incremental build が bundled source の変更を fingerprint に含めるか
- golden と diagnostics が fileID 順序や virtual path に依存して揺れないか

### 読み込みフェーズ

#### Source origin

`SourceManager` に origin を持たせる。

| origin | 例 | 用途 |
|---|---|---|
| `user` | CLI 入力の実パス | 通常診断、metadata export、golden の主対象 |
| `bundledStdlib` | `__bundled_kotlin/text/StringComparison.kt` | implicit stdlib source、metadata export から除外 |
| `residualStdlib` | `__bundled_kotlin_text_stdlib.kt` | 移行前 API の暫定 source、削除予定を追跡 |

既存の `__bundled_` prefix は、metadata export 除外やテストフィルタで使われているため維持する。ただし prefix 判定だけに依存せず、origin を source of truth にする。互換期間は `path.hasPrefix("__bundled_")` も残す。

#### Load order

`LoadSourcesPhase` は次の順序で登録する。

1. bundled stdlib source を virtual path で登録する
2. residual stdlib source を virtual path で登録する
3. ユーザー入力を実パスで登録する

Bundled source は relative path で昇順ソートし、SwiftPM の resource 列挙順やファイルシステム順に依存しない。ユーザー入力は CLI 指定順を維持する。

この順序により fileID は安定する。golden では fileID の数値を期待値に直接出さず、source path と source position から安定キーを作る。

#### Opt-out

stdlib source の opt-out は `CompilerOptions` に専用プロパティを追加して表現する。

- CLI alias: `-no-default-stdlib-sources`
- frontend flag: `-Xfrontend no-default-stdlib-sources`
- test helper: `includeDefaultStdlibSources: false`

既存の `--no-stdlib` / `includeStdlib` は search path や link-time stdlib の意味を持つため、bundled source の opt-out と混同しない。互換性のため `--no-stdlib` が bundled source も止めるかは別 PR で明示的に決める。

#### 診断パス

ユーザー入力の読み込み失敗はこれまで通り `KSWIFTK-SOURCE-0002` と実パスを出す。bundled source の読み込み失敗は compiler packaging の問題なので、ユーザー入力とは別コードにする。

- `KSWIFTK-SOURCE-0101`: bundled stdlib resource directory is unavailable
- `KSWIFTK-SOURCE-0102`: bundled stdlib source could not be read

通常の parser / sema diagnostics は virtual path を表示してよいが、JSON/LSP では origin を含め、ユーザーが編集できない implicit file であることを区別できるようにする。

### 合成スタブとの優先順位

#### 基本規則

Stdlib source 宣言を authoritative とする。

1. ユーザー宣言は通常の Kotlin 名前解決規則で扱う
2. bundled stdlib source 宣言があるシグネチャは synthetic stub を登録しない
3. residual stdlib source は bundled stdlib source と同じ優先度だが、削除予定として分類する
4. synthetic stub は stdlib source が未配線の API だけを補う

ここでいう「同シグネチャ」は少なくとも次を含む。

- package FQName
- declaration kind
- simple name
- receiver type
- value parameter arity and types
- type parameter arity
- return typeは警告メッセージに含めるが、skip 判定の主キーにはしない

#### 登録フロー

`SemaPhase` の synthetic registration 前に、AST から stdlib source declaration index を作る。

```text
ASTModule
  -> StdlibSourceDeclarationIndex
  -> Synthetic registration guard
  -> SymbolTable
```

synthetic 登録ヘルパーは、登録前に index へ問い合わせる。

- 同シグネチャの stdlib source 宣言がある場合: stub 登録を skip
- 同名だがシグネチャが異なる場合: overload として登録可能
- 同シグネチャの stdlib source と synthetic stub が両方登録されそうな場合: warning を出して synthetic を skip

warning は移行 PR の監査用であり、通常ユーザーには出しすぎない。まず `-Xfrontend warn-stdlib-shadowed-stubs` のような開発用 flag で有効化し、RF-STDLIB-004 以降の縦切り PR で必要なら default warning 化する。

#### 二重定義の扱い

二重定義は次のように分ける。

| 組み合わせ | 扱い |
|---|---|
| stdlib source vs synthetic stub | warning、synthetic を skip |
| bundled stdlib source vs residual stdlib source | warning、bundled source を優先 |
| user source vs bundled stdlib source | 通常の名前解決と重複診断。stdlib source を隠すための特殊扱いはしない |
| user source vs synthetic stub | 既存の shadowing 規則を維持し、必要な箇所だけ source 宣言化で解消 |

### インクリメンタルキャッシュ

#### Fingerprint

incremental mode は user input だけでなく implicit stdlib source も入力集合に含める必要がある。

`IncrementalCompilationCache.computeCurrentFingerprints` には、次の logical input list を渡す。

1. ユーザー入力パス
2. bundled stdlib virtual path と content hash
3. residual stdlib virtual path と content hash
4. stdlib source manifest version

ファイルシステム実パスではなく virtual path + contents で fingerprint する。SwiftPM resource の展開先が build directory ごとに変わっても cache key が揺れないようにする。

#### Build configuration hash

`IncrementalBuildConfiguration` には次を追加する。

- stdlib source manifest hash
- include default stdlib sources flag
- residual stdlib source version

`time-phases` や `jobs=N` と同じく出力非影響 flag は除外するが、stdlib source opt-out は出力に影響するので hash に含める。

#### Frontend state reuse

stdlib source は多くのユーザー入力から参照される。stdlib source fingerprint が変わった場合、dependency graph が完全でない期間は full frontend rebuild に落とす。依存関係が symbol-level に十分記録できるようになった後で、stdlib source に依存するユーザーファイルだけを再解析する。

RF-STDLIB-006 の pre-parse cache は、既存の `IncrementalFrontendState` を拡張して次を分けて保存する。

- stdlib-only interner snapshot
- stdlib AST snapshot
- stdlib symbol seed

初期実装では AST snapshot までを目標にし、Sema symbol seed は synthetic registration skip が安定してから検討する。

### Golden と diff ハーネス

#### FileID と出力順

Golden は fileID 数値を期待値にしない。表示順が必要な場合は次の sort key を使う。

1. source origin: user, bundled stdlib, residual stdlib
2. normalized path
3. source offset
4. declaration stable key

通常の user-facing golden は user origin を主対象にし、stdlib 宣言は「参照された required symbol」だけを表示する。stdlib pipeline 自体の golden では bundled origin を明示的に含める。

#### 診断ソート

diagnostics は source location sort の前に origin と path を安定化する。virtual path は `/private/...` の resource 展開先を含めない。`__bundled_` path をそのまま使う。

#### diff_kotlinc.sh

`Scripts/diff_kotlinc.sh` は implicit stdlib source 込みを default とする。stdlib source pipeline を切り分ける regression では、kswiftc 側だけ `-Xfrontend no-default-stdlib-sources` を使えるようにして、synthetic fallback との差分を見られるようにする。

### コンパイル時間戦略

#### 計測

RF-STDLIB-006 では `-Xfrontend time-phases` で次を比較する。

- bundled stdlib source なし
- bundled stdlib source あり
- bundled + residual source あり

最低限 `LoadSources`, `Lex`, `Parse`, `BuildAST`, `SemaPasses` の増分を記録する。必要なら `PhaseTimer.recordSubPhase` で `LoadBundledStdlib` と `ParseBundledStdlib` を分ける。

#### 許容ライン

常時 stdlib source による overhead は、Smoke 相当の小さい入力で次を目安にする。

- wall-clock 15% 未満、または 200 ms 未満
- golden suite で 10% 未満
- `diff_kotlinc.sh` shards で 10% 未満

これを超える場合は pre-parse cache を導入する。

#### Pre-parse cache

pre-parse cache の key は以下。

- compiler version or frontend schema version
- stdlib source manifest hash
- parser/AST schema version
- output-affecting frontend flags

保存対象は段階導入する。

1. lex/parse 結果
2. AST snapshot
3. source declaration index
4. sema seed

最初から sema seed まで入れると synthetic registration skip と type interning の不変条件が重くなるため、RF-STDLIB-006 では 1 または 2 までを候補にする。

### E2E 縦切りテンプレート

RF-STDLIB-004 以降の各移行 PR は、同じチェックリストで進める。

1. 対象 API を `Sources/CompilerCore/Stdlib` の `.kt` へ置く
2. bundled source として `LoadSourcesPhase` から読まれることを確認する
3. 同シグネチャ synthetic stub が skip されることをテストする
4. TypeCheck fallback を削除する
5. KIR/CallLowerer の direct `kk_*` dispatch を source-backed symbol 経由へ変える
6. Runtime `@_cdecl` を削除するか、`kswiftk.internal.__*` bridge に降格する
7. RuntimeABISpec と ABI parity テストを更新する
8. golden と `diff_kotlinc.sh` を更新する

`StringComparison.kt` の `commonPrefixWith` / `commonSuffixWith` を最初の縦切りにする。次に `StringSplitJoin.kt` を移行し、`kk_string_split*` 直接 dispatch を Kotlin 層経由に置換する。

### 完了条件

RF2 の完了条件は次の通り。

- bundled stdlib source が default でコンパイルに含まれる
- opt-out がテストから使える
- SourceManager が source origin を保持する
- stdlib source 宣言が synthetic stub より優先される
- duplicated source/stub surface を warning で検出できる
- incremental cache が implicit stdlib source を fingerprint と build hash に含める
- golden と diagnostics が deterministic に並ぶ
- compile-time overhead が PhaseTimer で記録され、閾値超過時の cache 方針が実装される

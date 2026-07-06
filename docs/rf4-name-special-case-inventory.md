# RF4 Name-Based Special Case Inventory

RF-SEMA-001 inventory for direct `interner.resolve(...) == "name"` special handling in
`Sources/CompilerCore/Sema/TypeCheck`.

Baseline command:

```bash
rg -n 'interner\.resolve\([^\n]+\)\s*(==|!=)|((==|!=)\s*interner\.resolve\()' Sources/CompilerCore/Sema/TypeCheck
```

On this HEAD the current count is 102 direct comparison lines after the first RF-SEMA-002
slices. Earlier RF4 notes mentioned 104 and this document previously recorded 110 before
the first metadata slice; use this document plus the command above as the current
branch-local source of truth.

| 機能 | 対応スタブ / 移行先 | スタブ/ソース移行後に削除可能か |
|---|---|---|
| `repeat(times) {}` top-level loop special path (`CallTypeChecker.swift`) | `HeaderHelpers+SyntheticStdlibLoopStubs`; now carries `.repeatLoop` via `SymbolTable.setStdlibSpecialCallKind` | Yes for name guard: migrated in RF-SEMA-002 slice 1. Remaining TypeCheck block is for lambda expected type and KIR special lowering until ordinary resolution can bind both. |
| `measureTimeMillis {}` (`kotlin.system`) | `HeaderHelpers+SyntheticTODOAndIOStubs`; now carries `.measureTimeMillis` via symbol metadata | Yes for name guard: migrated in RF-SEMA-002 slice 1. Remaining block exists because KIR lowering consumes `stdlibSpecialCallKind` and discards lambda result. |
| `measureTimeMicros {}` (`kotlin.system`) | `HeaderHelpers+SyntheticTODOAndIOStubs`; now carries `.measureTimeMicros` via symbol metadata | Yes for name guard: migrated in RF-SEMA-002 slice 1. Same remaining lowering constraint as `measureTimeMillis`. |
| `measureNanoTime {}` (`kotlin.system`) | `HeaderHelpers+SyntheticTODOAndIOStubs`; now carries `.measureNanoTime` via symbol metadata | Yes for name guard: migrated with the system timing common path. Same remaining lowering constraint as millis/micros. |
| `measureTime {}` / `measureTimedValue {}` (`kotlin.time`) | `HeaderHelpers+SyntheticTODOAndIOStubs` Duration/TimedValue stubs | Yes after kind metadata is attached and return-type construction is driven by resolved stub signature. |
| `Array(size)`, primitive array constructors, atomic array factories | Array/atomic synthetic constructor stubs; `KnownCompilerNames.isPrimitiveArrayConstructorTypeName` already avoids raw string for the entry guard | Partially. Constructor element-type inference still needs special code; name-to-element switch can move to constructor metadata. |
| `typeOf<T>()` | CInterop/typeOf synthetic stub and `.typeOf` lowering | Yes after typeOf stub carries kind and reified type result metadata. |
| `suspendCoroutineUninterceptedOrReturn` | `HeaderHelpers+SyntheticCoroutineRegistry`; already resolves visible synthetic symbol by FQ name | Yes after stub carries special kind. |
| `enumValues`, `enumValueOf`, `enumEntries` | `HeaderHelpers+SyntheticEnumStubs` plus `CallTypeChecker+EnumStdlib` | Mostly. Existing helper is already symbol-aware; remaining enum name checks can become metadata filters. |
| `maxOf` / `minOf` primitive fixed-arity fast path | `HeaderHelpers+SyntheticComparisonStubs`; `CallTypeChecker+Comparisons` | Yes after comparison stubs carry numeric-family metadata instead of switching on resolved name. |
| `compareBy`, `compareByDescending`, `compareValuesBy` | `HeaderHelpers+SyntheticComparisonStubs` | Yes after selector/vararg metadata is registered; source stdlib may remove some inference scaffolding. |
| `contract`, `implies`, `returns`, `returnsNotNull`, `callsInPlace`, `InvocationKind` | Contract DSL synthetic declarations / source DSL model | No until contract DSL is declaration-driven. Then callable IDs and enum constants can replace all string checks. |
| `sequence`, `iterator`, `generateSequence` | Sequence builder/source stdlib stubs | Partially. Lambda expected types and sequence element binding still need semantic metadata. |
| `delay`, coroutine launchers, flow factories, `asFlow` | Coroutine/Flow synthetic stubs | Yes after coroutine/flow factory metadata describes builder kind, receiver family, and lambda role. |
| `DeepRecursiveFunction`, `DeepRecursiveScope.callRecursive` | `HeaderHelpers+SyntheticDeepRecursiveStubs` | Yes after receiver class and member links are queried by symbol IDs / external link names. |
| `Worker.execute` | `HeaderHelpers+SyntheticNativeConcurrent*`; external link `kk_worker_execute` already used in one branch | Yes after the owner check uses symbol IDs or external link metadata consistently. |
| Builder DSL `send` | Builder DSL synthetic declarations | Yes after builder receiver scope metadata replaces name probing. |
| `length`, `code`, `OpenEndRange` | Primitive/String/Range surface declarations | Yes after these are ordinary properties/classes resolved by symbol ID, not fallback names. |
| `digitToInt`, `digitToIntOrNull` | `HeaderHelpers+SyntheticCharStubs` | Yes once char extension overloads are complete enough to remove no-candidate fallback. |
| String fallback family: `toByteArray`, `removeSurrounding`, `replaceIndentByMargin`, `replaceFirst`, `replaceRange`, `removeRange`, `replace`, `trimMargin`, `chunkedSequence`, `windowedSequence`, `orEmpty`, `equals`, `compareTo` | `HeaderHelpers+SyntheticString*` and bundled `Stdlib/kotlin/text/*` source | Yes after source/stub declarations provide overloads, defaults, and receiver-specific metadata. These are RF-SEMA-003 candidates. |
| Primitive fallback family: `inv`, `coerceIn`, `toString`, `hashCode`, `equals` | Primitive synthetic member declarations / operator metadata | Yes after primitive members are declared with operator/external-link metadata. These are RF-SEMA-003 candidates. |
| Collection fallback family: `flatten`, `binarySearch`, `filterIsInstance`, `filterIsInstanceTo`, `filterNotNullTo`, `toCollection`, `groupingBy`, HOF name sets | `HeaderHelpers+SyntheticCollection*`, `HeaderHelpers+SyntheticList*`, source `Stdlib/kotlin/collections/*` | Partially. Receiver classification should move first to `ReceiverClassifier` (RF-SEMA-004), then each HOF fallback can shrink. |
| File/Path/IO fallback family: `java.io.File`, `kotlin.io.path.Path`, `useLines`, `read`, `readValue` | `HeaderHelpers+SyntheticFileIOStubs`, `HeaderHelpers+SyntheticPathStubs`, delegate stubs | Yes after IO stubs expose complete signatures and owner receiver metadata. |
| Native interop `alloc` and related receiver FQ checks | Native/CInterop synthetic stubs | Yes after allocation APIs are resolved by receiver symbol and external link metadata. |
| `LinkedHashSet`, `atomicArrayOf`, `AtomicIntArray`, `AtomicLongArray` | Collection/atomic synthetic factory stubs | Yes after factory stubs carry constructor/factory metadata and expected return type rules. |
| `println` | IO synthetic top-level function | Yes after ordinary overload resolution covers the fast path. |
| Interface-super qualifier comparison | Nominal symbol lookup in `CallTypeChecker+MemberCallInferenceRegularResolution` | No stub dependency; replace with interned-name or symbol-based qualifier matching. |

Follow-up order:

1. Complete RF-SEMA-002 by migrating the remaining stdlib-special call guards to
   `stdlibSpecialCallKind(forSymbol:)`.
2. Use this inventory to peel RF-SEMA-003 no-candidate fallbacks by feature family.
3. Extract RF-SEMA-004 `ReceiverClassifier` before deleting collection fallback blocks.

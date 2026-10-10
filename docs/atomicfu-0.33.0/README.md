# kotlinx.atomicfu 0.33.0 API reference

This directory pins the upstream reference used by KUU-1732. It is an API
inventory and registration plan; the copied API dumps are not compiler inputs
and do not claim that atomic operations are implemented.

## Pinned upstream

- Repository: [Kotlin/kotlinx-atomicfu](https://github.com/Kotlin/kotlinx-atomicfu)
- Commit: [fc175fc575419ca9eae0d3c14cefe9c5cd7ca351](https://github.com/Kotlin/kotlinx-atomicfu/commit/fc175fc575419ca9eae0d3c14cefe9c5cd7ca351)
- Version: 0.33.0
- Kotlin reference version: 2.3.10
- The hashes below are Git blob SHA-1 values for the exact upstream file bytes.
  The local JVM API snapshot omits one empty final line so repository
  whitespace checks stay clean; the checker restores that byte before hashing.

| Reference | Upstream path | Git blob SHA-1 |
| --- | --- | --- |
| KLIB declarations | `atomicfu/api/atomicfu.klib.api` | `d170cb60f282c47b96d2c98041a7f5f2bf2e5850` |
| JVM declarations | `atomicfu/api/atomicfu.api` | `43d0bf802a601d72d49c8269bcfc325aa57eefac` |

The generated declaration index preserves each KLIB ABI identity instead of
collapsing declarations that share rendered text. It contains **150
common/native declarations** across **126 unique rendered signatures**. Five
additional JS/Wasm-only declaration identities (four unique signatures) are
listed as exclusions after resolving `Targets` comments through enclosing
class/property scopes. This prevents children of a JS/Wasm-only
`ReentrantLock` or `Lock` declaration from being misreported as native API.
The earlier flat pass's 130 unique rendered-signature count is retained in the
index summary for comparison. The full declaration text and target comments
remain in `reference/atomicfu.klib.api`; the JVM-only comparison stays separate
in `reference/atomicfu.api`.

Run `python3 Scripts/generate_atomicfu_api_index.py --write` to regenerate
`reference/atomicfu.common-native.declarations.json` deterministically. Each of
its 155 rows records the exact rendered signature, ABI identity, declaration kind,
overload group/index, effective KLIB target expression, Kotlin visibility,
source path and source blob hash, and direct/inherited/file annotations.
Empty direct annotation lists carry an explicit evidence note and pinned source
reference. `python3 Scripts/check_atomicfu_api_reference.py` checks the API
blob hashes, target-aware declaration coverage, generated-index freshness, and
the unsupported names `compareAndExchange`, `load`, `store`, and `MemoryOrder`.

## Source annotation and visibility index

The KLIB dump records signatures, overloads, target sets, and ABI modifiers,
but it does not preserve all Kotlin source annotations or source visibility.
In particular, an ABI-visible `@PublishedApi internal` member must not be
mistaken for a Kotlin-public member. The following source files are pinned
source-of-truth for declaration visibility and annotations. The generated
index links each ABI identity to the applicable file(s), rather than relying
on this family summary:

| Target set | Upstream source path | Git blob SHA-1 | Annotation families present |
| --- | --- | --- | --- |
| common | `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/AtomicFU.common.kt` | `721d86023038690cb7feffda049188ce1d2d9979` | `@Deprecated`, `@InlineOnly`; JS-name annotations are target-specific |
| common | `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/OptionalJsName.kt` | `d27c84e83bb05240beb3049e5eea97c268ab9a09` | `@OptIn`, `@OptionalExpectation`, `@Retention`, `@Target`, `@Deprecated` |
| common | `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/Trace.common.kt` | `7105ca2e6fa124364460a12ab2ad6fa30c1b2476` | `@InlineOnly`, `@Suppress`, `@OptionalJsName` |
| common | `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/TraceFormat.kt` | `99969bfa0c250fff7f8aca7105fc27a8cba98a00` | `@InlineOnly`, `@Suppress`, `@OptionalJsName` |
| common | `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/locks/SynchronousMutex.kt` | `8de86a013b951a93838d206cbcaf63ba27180b2e` | `@OptIn` |
| common | `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/locks/Synchronized.common.kt` | `ae0ea685437c061c98ccfd2d6fade06b22258199` | — |
| common/concurrent | `atomicfu/src/concurrentMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt` | `d52c9593e8b6264e143a53e4f26200da9c8ecc13` | `@ExperimentalThreadBlockingApi`, `@RequiresOptIn`, `@Retention`, `@Target` |
| JS/Wasm audit exclusion | `atomicfu/src/jsAndWasmSharedMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt` | `acb538d055f2283bb0cdbcc821168b309011e267` | `@OptionalJsName`; file-level `@Suppress` |
| native | `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/AtomicFU.kt` | `61c33a9fdc20515562661fe063f6bf34ded1e038` | `@InlineOnly`, `@PublishedApi` |
| native | `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/Trace.kt` | `9d8dcbf2e7a2e4774cadb7024c717b260f4f8511` | `@Suppress` |
| native | `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/SynchronousMutex.kt` | `cd50f621c1057f7edf6595a37bb185da99b01868` | — |
| native | `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt` | `2cfa72ce247c6a2bd89560a1c70918d029c1e313` | `@ThreadLocal`, `@OptIn` |
| native | `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt` | `d1fb1e6c42649f4e05b6ad8a340052f6cbb14640` | `@ThreadLocal`, `@ExperimentalThreadBlockingApi` |
| native | `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/ThreadId.kt` | `acb782bd3ff0100f00b532b74fd2659cfd75d731` | — |

The API dump intentionally remains the machine-counted ABI inventory; the
generated declaration JSON is the review index for per-declaration annotation
and visibility details. Do not infer that an annotation is absent just because
it is not printed in the ABI dump. `OptionalJsName` itself appears in the KLIB
surface, while the four inherited JS/Wasm lock members carry their exact
target provenance in the index.

## Bundled source and private bridge plan

The resource loader recursively includes every `.kt` below
`Sources/CompilerCore/Stdlib/` and registers it under a deterministic
`__bundled_…` virtual path. Put future source-backed declarations below
`Sources/CompilerCore/Stdlib/kotlinx/atomicfu/`; for example,
`AtomicFU.kt` becomes `__bundled_kotlinx/atomicfu/AtomicFU.kt`. No separate
resource manifest is needed. The focused discovery test exercises this
directory shape without pretending that an atomic implementation exists.

Keep the Kotlin package as `kotlinx.atomicfu`, distinct from
`kotlin.concurrent` and `kotlin.concurrent.atomics`. Test wildcard,
fully-qualified, and alias imports against those existing standard-library
names before implementing wrappers.

When a later implementation needs runtime operations, Kotlin wrappers should
call private `__kk_*` bridge declarations whose names are checked against
`RuntimeABISpec` and linked runtime exports. Preserve the upstream API
boundary: do not expose internal runtime names as public `kk_*` declarations.
Do not add wrappers that return placeholders or pretend to provide atomic
semantics. The native reference delegates to Kotlin/Native's atomic types;
the KSwiftK implementation must establish real semantics and runtime coverage
before claiming an operation works.

This inventory does not add any Runtime or RuntimeABI symbol. Future bridge
changes must run `bash Scripts/validate_runtime_abi_links.sh` and the
corresponding runtime atomic tests.

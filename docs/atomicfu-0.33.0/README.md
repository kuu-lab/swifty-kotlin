# kotlinx.atomicfu 0.33.0 API reference

This directory pins the API and source evidence used by KUU-1732. Files below
`reference/sources/` are documentation inputs for the inventory tools; they are
not bundled compiler sources. Actual registration and operations remain pending
as described in [the implementation plan](../atomicfu-implementation-plan.md).

## Pinned reference and count definitions

The upstream version is **0.33.0**, commit
[`fc175fc575419ca9eae0d3c14cefe9c5cd7ca351`](https://github.com/Kotlin/kotlinx-atomicfu/commit/fc175fc575419ca9eae0d3c14cefe9c5cd7ca351),
with Kotlin reference version **2.3.10**.

| API snapshot | Upstream Git blob SHA-1 |
| --- | --- |
| `atomicfu/api/atomicfu.klib.api` | `d170cb60f282c47b96d2c98041a7f5f2bf2e5850` |
| `atomicfu/api/atomicfu.api` | `43d0bf802a601d72d49c8269bcfc325aa57eefac` |

The local JVM API snapshot trims one empty final line for repository whitespace
checks; the checker restores that byte before hashing. The Native declaration
index has **150 common/native ABI identities**, **126 unique rendered
signatures**, and Kotlin visibility totals **142 public + 8 PublishedApi
internal**. The original flat count of **130** includes four rendered signatures
from **five JS/Wasm-only identities**, which remain explicit exclusions. These
counts measure different things; none is a count of implemented operations.

KLIB effective targets are inherited through nominal/property scopes before
counting. The five excluded identities are the JS/Wasm `Lock` getter and
`ReentrantLock` constructor/lock/tryLock/unlock. They are not added to Native
coverage. The Native source `ReentrantLock` is a `SynchronizedObject` typealias,
not a new JS/Wasm nominal class.

## Exact source evidence

The Linux source JAR used to acquire the available bytes is
`atomicfu-linuxx64-0.33.0-sources.jar`, SHA-256
`c42fc0a74388a147e40ab03b2c084c8e84f7a3620f58b19bb3b72ff417396a25`.
`atomicfu.source-manifest.json` pins **13 available source files**: the original
12 common/native files plus `MangledJsNames.kt`, needed to resolve annotation
constant expressions. Its fourteenth entry is the unavailable JS/Wasm source.
The local `reference/sources/.gitattributes` lists only these 13 pinned files
with `whitespace=-blank-at-eol` so upstream comment whitespace remains byte-exact.
Other paths, including compiler resources, retain normal whitespace checks.
All 150 Native identities have actual source evidence. The five excluded
JS/Wasm source references explicitly carry null visibility/annotation facts;
no annotation names or arguments are inferred for that missing file.

| Upstream source path | Git blob SHA-1 | Evidence |
| --- | --- | --- |
| `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/AtomicFU.common.kt` | `721d86023038690cb7feffda049188ce1d2d9979` | exact bytes vendored |
| `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/OptionalJsName.kt` | `d27c84e83bb05240beb3049e5eea97c268ab9a09` | exact bytes vendored |
| `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/Trace.common.kt` | `7105ca2e6fa124364460a12ab2ad6fa30c1b2476` | exact bytes vendored |
| `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/TraceFormat.kt` | `99969bfa0c250fff7f8aca7105fc27a8cba98a00` | exact bytes vendored |
| `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/locks/Synchronized.common.kt` | `ae0ea685437c061c98ccfd2d6fade06b22258199` | exact bytes vendored |
| `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/locks/SynchronousMutex.kt` | `8de86a013b951a93838d206cbcaf63ba27180b2e` | exact bytes vendored |
| `atomicfu/src/concurrentMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt` | `d52c9593e8b6264e143a53e4f26200da9c8ecc13` | exact bytes vendored |
| `atomicfu/src/jsAndWasmSharedMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt` | `acb538d055f2283bb0cdbcc821168b309011e267` | unavailable; excluded JS/Wasm only |
| `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/AtomicFU.kt` | `61c33a9fdc20515562661fe063f6bf34ded1e038` | exact bytes vendored |
| `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/Trace.kt` | `9d8dcbf2e7a2e4774cadb7024c717b260f4f8511` | exact bytes vendored |
| `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/ParkingSupport.kt` | `d1fb1e6c42649f4e05b6ad8a340052f6cbb14640` | exact bytes vendored |
| `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/Synchronized.kt` | `2cfa72ce247c6a2bd89560a1c70918d029c1e313` | exact bytes vendored |
| `atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/locks/SynchronousMutex.kt` | `cd50f621c1057f7edf6595a37bb185da99b01868` | exact bytes vendored |
| `atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/MangledJsNames.kt` | `8c37d016e4dc075d35f9f9910b354b18976ad0f3` | exact bytes vendored |

`atomicfu.source-anchors.json` maps each ABI identity to an exact declaration
line, character offset, header, and optional nominal owner in those immutable
bytes. It disambiguates overloads, explicit/implicit constructors and generated
property accessors. The schema-2 declaration index retains ABI signature/identity,
effective targets, kind, overload grouping, visibility, and source provenance.
For each source reference it keeps:

- direct annotations separately from enclosing class/property context and file
  annotations; a class annotation is not invented as a constructor annotation;
- raw annotation spelling, use-site target, named/positional argument expressions,
  source range and line; `BINARY`, opt-in `ERROR`, deprecation `WARNING`, messages,
  `ReplaceWith` expressions and Target sets remain distinguishable;
- symbolic argument expressions plus the exact pinned constant declaration when
  present, rather than a guessed JavaScript name;
- explicit unknown evidence for unavailable excluded source.

The legacy `inherited_annotations` field contains property-accessor source
context only; it is not a claim of Kotlin annotation inheritance. For example,
`AtomicIntArray` and `AtomicLongArray` explicit constructors have direct
`Deprecated` only, while their class annotations are separate context.
`TraceBase` and its `None`/append/invoke members come from `Trace.common.kt`;
only the actual Trace factory/named/default-format declarations point to Native
`Trace.kt`. Scalar `toString` overrides exist in Native `AtomicFU.kt` only.

## Regeneration and independent checks

```bash
python3 Scripts/generate_atomicfu_api_index.py --write
python3 Scripts/check_atomicfu_api_reference.py
python3 Tests/Scripts/test_atomicfu_api_index.py
```

The checker SHA-verifies source bytes and compares indexed facts with annotations
read from the pinned declarations before checking deterministic JSON freshness.
It independently rejects incorrect object kinds, source path sets, visibility,
annotation arguments, callable arity, atomic factory overload types and extension
receiver substitutions. Regression tests fix concrete upstream source facts and
mutate semantic facts/anchors; they do not obtain expected annotations from the
generator. The reader is deliberately for this pinned syntax, not a general Kotlin
parser or proof of arbitrary Kotlin type resolution.

CI's repository-checks job runs the checker and focused Python tests. A green
inventory check establishes the ledger's pinned facts, not source-backed symbol
binding, Runtime ABI correctness, or execution. Those gates remain required by
[the implementation plan](../atomicfu-implementation-plan.md).

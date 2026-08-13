---
name: Swifty-Kotlin Sema Refactor Verification
description: End-to-end verification workflow for test-only Sema consolidation PRs in kuu-lab/swifty-kotlin.
---

# Swifty-Kotlin Sema Refactor Verification

## Devin Secrets Needed
None.

## When to use
- The PR touches only `Tests/CompilerCoreTests/Sema/*.swift` (or adds small source fixes for Sema lookup).
- You need to prove the compiler still builds and the refactored Sema tests pass.

## Standard gate sequence

```bash
swift package clean
swift build
bash Scripts/swift_test.sh --filter SmokeTests -Xswiftc -swift-version -Xswiftc 6
bash Scripts/swift_test.sh --filter CompilerCoreTests -Xswiftc -swift-version -Xswiftc 6
bash Scripts/validate_runtime_abi_links.sh -Xswiftc -swift-version -Xswiftc 6
```

- `CompilerCoreTests` covers all Sema/front-end suites including `AnnotationSemanticTests`.
- For a focused check, use `--filter "RandomSynthetic|Uuid"` or suite-name regexes.

## `diff_kotlinc.sh` guidance

- The full `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` gate is **very long** (799 `.kt` files, 8 workers, often 30+ minutes) and prints nothing until completion.
- In an interactive session, run a targeted subset covering the changed API surfaces instead, e.g.:

```bash
mkdir -p /tmp/diff_subset
cp Scripts/diff_cases/{duration,math,native,property,random,range,uuid,string}*.kt /tmp/diff_subset/
DIFF_RUN_TIMEOUT=30 bash Scripts/diff_kotlinc.sh /tmp/diff_subset
```

- The full directory gate should be delegated to CI or a dedicated long runner.
- Requires JDK >= 21, `kotlinc` 2.3.10, and `KSWIFTK_LLVM_DYLIB` set.

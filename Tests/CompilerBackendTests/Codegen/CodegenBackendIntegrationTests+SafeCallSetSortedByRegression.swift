#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSafeCallSetSortedByRegressionTests {

    // DEBT-DIFF-006 regression: `Map.entries` (a Set<Map.Entry<K, V>>) calling
    // `sortedBy`, both directly and through a safe-call chain (`?.`).
    //
    // Root cause 1 (KIR lowering, callee name): CallLowerer+SafeMemberCalls.swift's
    // lowerSafeMemberCallExpr, when it couldn't recover a call binding for the
    // callee, fell back to the bare Kotlin function name as the LLVM external
    // symbol for anything that wasn't one of a fixed list of coroutine-handle
    // member names (await/join/cancel/...) — instead of reusing the same
    // name-based collection/synthetic dispatch (`loweredMemberCalleeName`) that
    // the regular (non-safe) member call path already uses. This produced an
    // unresolved `_sortedBy` linker symbol for `x?.entries?.sortedBy { ... }`.
    // Fixed by reusing `loweredMemberCalleeName` for the callee name (matching
    // `emitMemberCallInstruction`'s exact `hasHOFLambdaArg` computation via
    // `sema.bindings.isCollectionHOFLambdaExpr`, not a generic syntactic
    // "is this a lambda" check — the two disagree for `sortedBy`, whose lambda
    // is never marked via `markCollectionHOFLambdaExpr`, and a mismatched
    // dispatch key resolves to the wrong runtime entry point).
    //
    // Root cause 2 (Runtime ABI): once the callee correctly resolved to
    // `kk_list_sortedBy`, that native entry point only accepted `RuntimeListBox`
    // handles (via `runtimeListBox(from:)`) and panicked on `RuntimeSetBox`
    // (which is what `Map.entries` returns), even though `sortedBy` is defined
    // on `Iterable<T>` in Kotlin and so must accept any concrete collection
    // receiver. Fixed by switching to the existing `runtimeCollectionElements(from:)`
    // helper (RuntimeCollectionHelpers.swift), which already handled both List
    // and Set — `kk_list_sortedBy` just wasn't using it.
    //
    // Root cause 3 (KIR lowering, receiver argument): even with the callee name
    // fixed, `lowerSafeMemberCallExpr`'s `chosen == nil` branches never inserted
    // the receiver into the call's argument list (mirroring a gap already worked
    // around for `Random.nextInt`/`nextLong` in the regular, non-safe path — see
    // the "when Sema failed to resolve nextLong/nextInt on Random" comment in
    // CallLowerer+MemberCallEmission.swift), so the native function received a
    // garbage/misaligned argument list. Fixed by reusing the exact same shared
    // helper the regular path already calls for this
    // (`appendReceiverToMemberArguments`, CallLowerer+MemberCallEmission.swift)
    // instead of hand-rolling the insertion.
    //
    // Remaining known gap (separate, Sema-level, not fixed here): a member call
    // that resolves to a *real* `chosenCallee` in the regular (non-safe) path —
    // e.g. plain `joinToString` (with or without a transform lambda), which is
    // not in `unresolvedCollectionMemberNames` and so is never expected to reach
    // the name-based KIR fallback at all — can still end up with
    // `chosenCallee == nil` when the exact same call is written as a safe-call
    // (`x?.joinToString(...)`) instead of a plain dot-call. That is a Sema
    // overload-resolution gap specific to the safe-call inference path, not an
    // argument-passing bug, and needs its own investigation. `testCodegenSetSortedByThroughSafeCallChain`
    // below routes around it with an explicit null check before the
    // `joinToString` call; `Scripts/diff_cases/compiler_plugin_api.kt` routes
    // around it (and predates the discovery) with `?.let { ... }`.
    @Test
    func testCodegenSetSortedByDirectCall() throws {
        let source = """
        fun main() {
            val m = mapOf("b" to "2", "a" to "1")
            val sorted = m.entries.sortedBy { it.key }
            println(sorted.joinToString(",") { "${it.key}=${it.value}" })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SetSortedByDirect",
            expected: "a=1,b=2\n"
        )
    }

    // `sortedBy` itself now runs through the real safe-call chain
    // (`holder?.options?.entries?.sortedBy { ... }`), exercising the KIR
    // fixes above end to end. The `joinToString` call afterwards is guarded
    // by an explicit null check (rather than `?.`) to route around the
    // separate, still-open Sema gap described above.
    @Test
    func testCodegenSetSortedByThroughSafeCallChain() throws {
        let source = """
        data class Holder(val options: Map<String, String>)

        fun main() {
            val holder: Holder? = Holder(mapOf("b" to "2", "a" to "1"))
            val sorted = holder?.options?.entries?.sortedBy { it.key }
            if (sorted != null) {
                println(sorted.joinToString(",") { "${it.key}=${it.value}" })
            } else {
                println("null")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SetSortedBySafeCallChain",
            expected: "a=1,b=2\n"
        )
    }

    // Matches the `?.let { entries -> entries.sortedBy { ... }.joinToString
    // { ... } }` shape used in Scripts/diff_cases/compiler_plugin_api.kt: the
    // safe-call stops at `.let`, and both `sortedBy` and `joinToString` run
    // inside it on the smart-cast non-null parameter, going through the
    // regular (non-safe) member-call path throughout. Kept as its own
    // regression since it predates (and is independent of) the safe-call
    // fixes above.
    @Test
    func testCodegenSetSortedByInsideSafeCallLet() throws {
        let source = """
        data class Holder(val options: Map<String, String>)

        fun main() {
            val holder: Holder? = Holder(mapOf("b" to "2", "a" to "1"))
            val summary = holder?.options?.entries?.let { entries ->
                entries.sortedBy { it.key }.joinToString(",") { "${it.key}=${it.value}" }
            }
            println("options=$summary")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SetSortedBySafeCallLet",
            expected: "options=a=1,b=2\n"
        )
    }
}
#endif

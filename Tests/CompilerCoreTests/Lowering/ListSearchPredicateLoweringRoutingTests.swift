#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// RF-LOWER-CALL-010: pin how the List search / predicate group
/// (`find*` / `indexOf*` / `contains*` / `count` / `any` / `all` / `none` /
/// `first*` / `last*`) is routed through `CollectionLiteralLoweringPass`.
///
/// KSP-423 moved every one of these List overloads to
/// `Stdlib/kotlin/collections/ListSearchHOF.kt`, so
/// `shouldPreserveSourceBackedAggregateCall` keeps the resolved Kotlin
/// declaration and no `kk_*` rewrite may fire for a List receiver.  That is
/// what makes the deleted List `count(predicate)` rewrite unreachable.
///
/// The same name allowlist is receiver-blind, so it still has to protect the
/// non-List rewrites.  `nonListReceiversKeepTheirRuntimeRewrites` fixes those
/// separately, so RF-LOWER-CALL-011/012 can tell a dead entry from a
/// load-bearing one instead of deleting by name.
@Suite
struct ListSearchPredicateLoweringRoutingTests {
    /// Every List search / predicate name in CALL-010's scope, with the
    /// overloads that `ListSearchHOF.kt` declares.
    private static let listSearchSource = """
    fun main() {
        val xs = listOf(1, 2, 3, 4, 5)
        println(xs.find { it > 3 })
        println(xs.findLast { it < 3 })
        println(xs.indexOf(3))
        println(xs.lastIndexOf(3))
        println(xs.indexOfFirst { it > 2 })
        println(xs.indexOfLast { it > 2 })
        println(xs.contains(3))
        println(xs.containsAll(listOf(1, 2)))
        println(xs.count())
        println(xs.count { it % 2 == 0 })
        println(xs.any())
        println(xs.any { it > 4 })
        println(xs.all { it > 0 })
        println(xs.none())
        println(xs.none { it > 9 })
        println(xs.first())
        println(xs.first { it > 2 })
        println(xs.last())
        println(xs.last { it < 4 })
        println(xs.firstOrNull())
        println(xs.firstOrNull { it > 9 })
        println(xs.lastOrNull())
        println(xs.lastOrNull { it > 9 })
    }
    """

    /// The Kotlin member names CALL-010 covers.
    private static let searchPredicateNames: Set<String> = [
        "find", "findLast", "indexOf", "lastIndexOf", "indexOfFirst",
        "indexOfLast", "contains", "containsAll", "count", "any", "all",
        "none", "first", "last", "firstOrNull", "lastOrNull",
    ]

    /// The overloads that carry a resolved `ListSearchHOF.kt` symbol and are
    /// therefore preserved by `shouldPreserveSourceBackedAggregateCall`.
    /// No-predicate overloads take just the receiver; predicate overloads take
    /// receiver + lambda.  `count/1` is absent on purpose — see
    /// `sourceBackedListSearchCallsSurviveCollectionLiteralLowering`.
    private static let preservedOverloads: Set<String> = [
        "find/2", "findLast/2",
        "indexOf/2", "lastIndexOf/2",
        "indexOfFirst/2", "indexOfLast/2",
        "contains/2", "containsAll/2",
        "count/2",
        "any/1", "any/2", "all/2",
        "none/1", "none/2",
        "first/1", "first/2", "last/1", "last/2",
        "firstOrNull/1", "firstOrNull/2",
        "lastOrNull/1", "lastOrNull/2",
    ]

    /// The four names RF-LOWER-CALL-010 dropped from
    /// `shouldPreserveSourceBackedAggregateCall` / `...VirtualCall` plus
    /// `containsAll`: no rewrite anywhere in either collection lowering pass
    /// keys on them, so preserving them by name was indistinguishable from
    /// the `loweredBody.append(instruction)` fallthrough.
    private static let namesWithoutAnyLoweringRewrite: Set<String> = [
        "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast", "containsAll",
    ]

    private static func runCollectionLiteralPassOnly(_ ctx: CompilationContext) throws -> KIRModule {
        let module = try #require(ctx.kir)
        let kirCtx = KIRContext(
            diagnostics: ctx.diagnostics,
            options: ctx.options,
            interner: ctx.interner,
            sema: ctx.sema
        )
        module.scanFeatures()
        try CollectionLiteralLoweringPass().run(module: module, ctx: kirCtx)
        return module
    }

    /// Direct `.call` instructions whose callee is one of `names`, with the
    /// resolved symbol and argument count (receiver included).
    private static func calls(
        in body: [KIRInstruction],
        matching names: Set<String>,
        interner: StringInterner
    ) -> [(name: String, argumentCount: Int, symbol: SymbolID?)] {
        body.compactMap { instruction in
            guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction else { return nil }
            let name = interner.resolve(callee)
            guard names.contains(name) else { return nil }
            return (name, arguments.count, symbol)
        }
    }

    // MARK: - source-backed routing (the production path)

    /// Every List overload stays a call to its `ListSearchHOF.kt` declaration,
    /// and no collection runtime bridge is substituted for it.
    @Test
    func sourceBackedListSearchCallsSurviveCollectionLiteralLowering() throws {
        try withTemporaryFile(contents: Self.listSearchSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ListSearchRouting",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let survivors = Set(
                Self.calls(in: body, matching: Self.searchPredicateNames, interner: ctx.interner)
                    .map { "\($0.name)/\($0.argumentCount)" }
            )
            #expect(
                survivors == Self.preservedOverloads,
                "every symbol-carrying List search/predicate overload must stay a source call; missing: \(Self.preservedOverloads.subtracting(survivors)), unexpected: \(survivors.subtracting(Self.preservedOverloads))"
            )

            let callees = extractCallees(from: body, interner: ctx.interner)

            // A bare `count()` is the one member of the group that never
            // reaches the preserve check: `CallLowerer+LegacyMemberLikeCalls`
            // emits it with `symbol: nil`, so `+CallRewriteCollectionMember`
            // rewrites it to the size bridge.  `ListSearchHOF.kt` defines
            // `count(): Int = size`, so this is equivalent — but it is a live
            // rewrite, not a dead one, and CALL-011 must not treat it as such.
            #expect(
                callees.filter { $0 == "__kk_list_size" }.count == 1,
                "bare count() must still reach __kk_list_size exactly once; callees: \(Set(callees).sorted())"
            )

            // Every other List rewrite in this group is shadowed by the
            // preserve check and must not appear.
            for forbidden in ["__kk_set_contains", "kk_map_count", "kk_list_count"] {
                #expect(
                    !callees.contains(forbidden),
                    "\(forbidden) must not replace a source-backed List search call; callees: \(Set(callees).sorted())"
                )
            }

            // The signature the deleted `count(predicate)` branch would have
            // produced: a `symbol: nil` call to the literal name `count` with
            // the receiver, lambda and closure word.  No runtime export of
            // that name exists, so it must never be emitted.
            let brokenCountRewrites = body.filter { instruction in
                guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction else { return false }
                return symbol == nil
                    && ctx.interner.resolve(callee) == "count"
                    && arguments.count == 3
            }
            #expect(
                brokenCountRewrites.isEmpty,
                "the legacy List count(predicate) rewrite must stay deleted; found \(brokenCountRewrites.count)"
            )
        }
    }

    /// The reason the rewrites are skipped: each callee resolves to a
    /// source-backed declaration in `ListSearchHOF.kt`.
    @Test
    func listSearchPredicateCalleesResolveToListSearchHOF() throws {
        try withTemporaryFile(contents: Self.listSearchSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ListSearchRoutingSymbols",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let searchCalls = Self.calls(in: body, matching: Self.searchPredicateNames, interner: ctx.interner)
            #expect(searchCalls.count == 23, "expected 23 search/predicate calls; got \(searchCalls.count)")

            // Bare `count()` is the sole overload BuildKIR leaves unbound.
            let unbound = Set(
                searchCalls.filter { $0.symbol == nil }.map { "\($0.name)/\($0.argumentCount)" }
            )
            #expect(
                unbound == ["count/1"],
                "only bare count() may reach lowering without a symbol; got \(unbound.sorted())"
            )

            let sema = try #require(ctx.sema)
            for call in searchCalls where call.symbol != nil {
                let label = "\(call.name)/\(call.argumentCount)"
                let symbolID = try #require(call.symbol)
                #expect(sema.symbols.isSourceBackedSymbol(symbolID), "\(label) must be source-backed")

                let fileID = try #require(sema.symbols.sourceFileID(for: symbolID), "\(label): missing source file")
                #expect(
                    ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListSearchHOF.kt",
                    "\(label) must resolve to ListSearchHOF.kt; got \(String(describing: ctx.sourceManager.path(of: fileID)))"
                )
            }
        }
    }

    /// `indexOf` / `lastIndexOf` / `indexOfFirst` / `indexOfLast` /
    /// `containsAll` are no longer named in either preserve allowlist.  No
    /// rewrite in the direct or virtual collection pass keys on them, so they
    /// must still survive untouched — that equivalence is what allowed the
    /// entries to go.
    @Test
    func namesWithoutAnyLoweringRewriteSurviveWithoutBeingPreservedByName() throws {
        try withTemporaryFile(contents: Self.listSearchSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ListSearchRoutingUnpreserved",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let sema = try #require(ctx.sema)

            let survivors = Self.calls(
                in: body,
                matching: Self.namesWithoutAnyLoweringRewrite,
                interner: ctx.interner
            )
            #expect(
                Set(survivors.map(\.name)) == Self.namesWithoutAnyLoweringRewrite,
                "all five must remain source calls; got \(Set(survivors.map(\.name)).sorted())"
            )
            for call in survivors {
                let symbolID = try #require(call.symbol, "\(call.name): must keep its resolved symbol")
                #expect(
                    sema.symbols.isSourceBackedSymbol(symbolID),
                    "\(call.name) must still resolve to its bundled Kotlin declaration"
                )
            }
        }
    }

    // MARK: - the non-List rewrites the shared allowlist still protects

    /// The allowlist is receiver-blind, so the entries kept for Range / Set /
    /// Map receivers are the reason `contains` / `count` / `find` could not go
    /// the way the five index names did.  Two distinct situations are pinned
    /// here: rewrites that still fire because nothing source-backed resolves
    /// (`__kk_list_size` for a bare `count()`, `__kk_set_contains`), and
    /// rewrites the preserve check shadows, which removing the name would
    /// re-enable (`kk_range_find`, `kk_map_count`).
    @Test
    func nonListReceiversKeepTheirRuntimeRewrites() throws {
        let source = """
        fun main() {
            val xs = listOf(1, 2, 3)
            println(xs.size)
            val s = setOf(1, 2, 3)
            println(s.contains(2))
            val m = mapOf(1 to "a", 2 to "b")
            println(m.count { it.key > 1 })
            val r = 1..10
            println(r.find { it > 7 })
            println(r.contains(5))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NonListSearchRewrites",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            #expect(
                callees.contains("__kk_list_size"),
                "List.size must still reach __kk_list_size; callees: \(callees.sorted())"
            )
            // Set.contains is not source-backed, so the preserve check does
            // not fire and `+CallRewriteCollectionMember` still rewrites it.
            #expect(
                callees.contains("__kk_set_contains"),
                "Set.contains must still reach __kk_set_contains; callees: \(callees.sorted())"
            )
            // `IntRange.find` is source-backed in RangeHOF.kt, so the
            // preserve check shadows the `kk_range_find` rewrite in
            // `+VirtualCallRewrite+Range.swift`.  Dropping `findName` from
            // the allowlist the way the five index names were dropped would
            // re-enable that rewrite and change the emitted call — which is
            // precisely why `findName` had to stay.
            #expect(
                !callees.contains("kk_range_find"),
                "source-backed IntRange.find must not reach kk_range_find; callees: \(callees.sorted())"
            )
            #expect(
                callees.contains("find"),
                "IntRange.find must stay a source call; callees: \(callees.sorted())"
            )
            // `IntRange.contains` IS declared in RangeMembership.kt:117, yet
            // the rewrite still fires: `CallLowerer+MemberCallEmission.swift:98`
            // emits range `contains` / `first` / `last` / `count` / `isEmpty` /
            // `sum` through a member fast path that binds no symbol, so the
            // preserve check's `guard let symbol` rejects them — the same
            // mechanism as a bare `List.count()`.  A source declaration alone
            // therefore does not tell you whether a rewrite is shadowed.
            #expect(
                callees.contains("__kk_range_contains"),
                "IntRange.contains must still reach __kk_range_contains; callees: \(callees.sorted())"
            )
            // Map.count(predicate) is source-backed in MapHOF.kt, and
            // `+CallRewriteFactories` guards it with its own
            // `isSourceBackedBundledFunction` check rather than the name
            // allowlist — so the runtime bridge must not appear.
            #expect(
                !callees.contains("kk_map_count"),
                "source-backed Map.count(predicate) must not reach kk_map_count; callees: \(callees.sorted())"
            )
        }
    }
}
#endif

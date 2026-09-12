#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// RF-LOWER-CALL-011: pin the *production* routing of the List `sorted*` /
/// `min*` / `max*` families.
///
/// KSP-426 (#5769) moved these APIs to `ListSortingHOF.kt` /
/// `ListExtremaHOF.kt` and emptied
/// `CollectionLiteralLoweringPass+CallRewriteHOFExtrema.swift`, but the
/// matching `kk_list_*` ABI entries in `RuntimeABISpec+CollectionHOF.swift`
/// were left behind as spec-only registrations: of the 19 names below only
/// `kk_list_sortedBy` still has a `@_cdecl` in `Sources/Runtime`.  A lowering
/// rewrite that redirected one of the resolved Kotlin declarations to those
/// names would therefore not fail a Core test — it would fail at link time, or
/// silently bind to an unrelated symbol.  Nothing pinned that.
///
/// RF-LOWER-CALL-011 then found the 25-name KSP-426 enumeration in
/// `shouldPreserveSourceBackedAggregateCall` (and its
/// `+VirtualCallRewrite.swift` mirror) to be unreachable — every rewrite that
/// could claim these names sits behind an outer member-name gate that never
/// listed them — and removed it.  These tests are what keeps that from
/// regressing: they assert the routing directly rather than the presence of a
/// name in an allowlist.
@Suite
struct ListSortExtremaLoweringRoutingTests {
    /// The legacy `kk_list_*` ABI surface for the List sorting/extrema APIs,
    /// as registered in `RuntimeABISpec+CollectionHOF.swift`.  Matched exactly
    /// so `kk_list_sorted` does not also match `kk_list_sortedWith`.
    static let legacyListSortExtremaRuntimeCallees: Set<String> = [
        "kk_list_sorted", "kk_list_sorted_primitive",
        "kk_list_sortedBy", "kk_list_sortedBy_primitive",
        "kk_list_sortedDescending", "kk_list_sortedDescending_primitive",
        "kk_list_sortedByDescending", "kk_list_sortedByDescending_primitive",
        "kk_list_sortedWith",
        "kk_list_max", "kk_list_maxOrNull", "kk_list_maxBy",
        "kk_list_maxByOrNull", "kk_list_maxOfOrNull",
        "kk_list_min", "kk_list_minOrNull", "kk_list_minBy",
        "kk_list_minByOrNull", "kk_list_minOfOrNull",
    ]

    /// Every callee name the removed KSP-426 block used to enumerate in the two
    /// policies (`shouldPreserveSourceBackedAggregateCall` in
    /// `+CallRewrite.swift` and `shouldPreserveSourceBackedVirtualCall` in
    /// `+VirtualCallRewrite.swift`), exercised on a `List` receiver.
    static let expectedSourceCallees: Set<String> = [
        "sorted", "sortedDescending", "sortedBy", "sortedByDescending", "sortedWith",
        "max", "min", "maxOrNull", "minOrNull",
        "maxBy", "minBy", "maxByOrNull", "minByOrNull",
        "maxOf", "minOf", "maxOfOrNull", "minOfOrNull",
        "maxWith", "minWith", "maxWithOrNull", "minWithOrNull",
        "maxOfWith", "minOfWith", "maxOfWithOrNull", "minOfWithOrNull",
    ]

    static let listSortExtremaSource = """
    fun main() {
        val nums = listOf(3, 1, 4, 1, 5)
        println(nums.sorted())
        println(nums.sortedDescending())
        println(nums.sortedBy { it })
        println(nums.sortedByDescending { it })
        println(nums.sortedWith { a, b -> a - b })
        println(nums.max())
        println(nums.min())
        println(nums.maxOrNull())
        println(nums.minOrNull())
        println(nums.maxBy { it })
        println(nums.minBy { it })
        println(nums.maxByOrNull { it })
        println(nums.minByOrNull { it })
        println(nums.maxOf { it })
        println(nums.minOf { it })
        println(nums.maxOfOrNull { it })
        println(nums.minOfOrNull { it })
        println(nums.maxWith { a, b -> a - b })
        println(nums.minWith { a, b -> a - b })
        println(nums.maxWithOrNull(naturalOrder()))
        println(nums.minWithOrNull(naturalOrder()))
        println(nums.maxOfWith(naturalOrder()) { it })
        println(nums.minOfWith(naturalOrder()) { it })
        println(nums.maxOfWithOrNull(naturalOrder()) { it })
        println(nums.minOfWithOrNull(naturalOrder()) { it })
    }
    """

    /// Runs only `CollectionLiteralLoweringPass`, so a failure names that pass
    /// rather than some later rewrite in `LoweringPhase`.
    static func runCollectionLiteralPassOnly(_ ctx: CompilationContext) throws -> KIRModule {
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

    /// `.call` / `.virtualCall` callees across *every* function in the module,
    /// not just `main`: a rewrite that fired inside an injected stdlib body
    /// would otherwise go unnoticed.
    static func allCallees(in module: KIRModule, interner: StringInterner) -> [String] {
        findAllKIRFunctions(in: module).flatMap { function in
            function.body.compactMap { instruction -> String? in
                switch instruction {
                case let .call(_, callee, _, _, _, _, _, _):
                    return interner.resolve(callee)
                case let .virtualCall(_, callee, _, _, _, _, _, _):
                    return interner.resolve(callee)
                default:
                    return nil
                }
            }
        }
    }

    /// The calls in `body` whose callee is one of the List sorting/extrema
    /// names, with the symbol the frontend resolved them to.
    static func sortExtremaCalls(
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [(name: String, symbol: SymbolID?)] {
        body.compactMap { instruction in
            guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else { return nil }
            let name = interner.resolve(callee)
            guard Self.expectedSourceCallees.contains(name) else { return nil }
            return (name, symbol)
        }
    }

    // MARK: - the no-redirect contract

    /// All 25 names survive `CollectionLiteralLoweringPass` as resolved source
    /// calls, and no legacy `kk_list_*` name reaches the lowered module.
    @Test
    func sourceBackedListSortAndExtremaCallsSurviveCollectionLiteralLowering() throws {
        try withTemporaryFile(contents: Self.listSortExtremaSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ListSortExtremaRouting",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let survivors = Set(Self.sortExtremaCalls(in: body, interner: ctx.interner).map(\.name))
            let missing = Self.expectedSourceCallees.subtracting(survivors).sorted()
            #expect(
                survivors == Self.expectedSourceCallees,
                "every List sorting/extrema call must stay a source call; missing: \(missing)"
            )

            let callees = Set(Self.allCallees(in: module, interner: ctx.interner))
            let redirects = callees.intersection(Self.legacyListSortExtremaRuntimeCallees)
            #expect(
                redirects.isEmpty,
                "no legacy kk_list_* sorting/extrema rewrite may reach lowered KIR; got \(redirects.sorted())"
            )
        }
    }

    /// Why the rewrite must not fire: each name resolves to a non-synthetic,
    /// source-backed declaration in the bundled Kotlin stdlib with no
    /// `externalLinkName` to bridge through.
    @Test
    func listSortAndExtremaCalleesResolveToBundledKotlinSource() throws {
        try withTemporaryFile(contents: Self.listSortExtremaSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ListSortExtremaSymbols",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let calls = Self.sortExtremaCalls(in: body, interner: ctx.interner)
            #expect(calls.count == 25, "expected 25 sorting/extrema calls; got \(calls.count)")

            let sema = try #require(ctx.sema)
            for call in calls {
                let symbolID = try #require(call.symbol, "\(call.name): production KIR must carry a resolved symbol")
                let symbol = try #require(sema.symbols.symbol(symbolID), "\(call.name): symbol must be in the table")

                #expect(!symbol.flags.contains(.synthetic), "\(call.name) must not resolve to a synthetic stub")
                #expect(
                    sema.symbols.externalLinkName(for: symbolID) == nil,
                    "\(call.name) must not carry an external link name"
                )
                #expect(sema.symbols.isSourceBackedSymbol(symbolID), "\(call.name) must be source-backed")

                let fileID = try #require(sema.symbols.sourceFileID(for: symbolID), "\(call.name): missing source file")
                let sourcePath = ctx.sourceManager.path(of: fileID)
                #expect(
                    sourcePath.hasPrefix("__bundled_kotlin/"),
                    "\(call.name) must resolve into the bundled Kotlin stdlib; got \(sourcePath)"
                )
            }
        }
    }

    /// A user function that merely shares one of the names — including on a
    /// `List` receiver, which is what the policy keys off — must be left alone
    /// and must never pick up a `kk_list_*` callee.
    @Test
    func userDefinedSortAndExtremaNamedFunctionsAreNotRewritten() throws {
        let source = """
        fun List<Int>.sortedWith(marker: Int): Int = marker + size

        fun List<Int>.maxOfWith(marker: String, selector: (Int) -> Int): String = marker + selector(size)

        fun main() {
            val nums = listOf(3, 1, 4)
            println(nums.sortedWith(1))
            println(nums.maxOfWith("m") { it })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ListSortExtremaShadowing",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            #expect(mainCallees.contains("sortedWith"), "the user sortedWith must stay; callees: \(mainCallees)")
            #expect(mainCallees.contains("maxOfWith"), "the user maxOfWith must stay; callees: \(mainCallees)")

            let callees = Set(Self.allCallees(in: module, interner: ctx.interner))
            #expect(
                callees.intersection(Self.legacyListSortExtremaRuntimeCallees).isEmpty,
                "a user function may never be rewritten to a runtime sorter; callees: \(callees.sorted())"
            )
        }
    }

    // MARK: - the receivers whose rewrites are still live

    /// `maxByOrNull` / `minByOrNull` are the two extrema names still listed in
    /// both policies, because they are shared with the Map group that
    /// RF-LOWER-CALL-012 owns.  They are as unreachable as the rest —
    /// `mapHOFRuntimeName` in `+CallRewriteHandlers.swift` maps them to
    /// `kk_map_maxByOrNull` / `kk_map_minByOrNull`, but `isCollectionHOFMemberName`
    /// gates that function and never lists them, and neither export has a
    /// `@_cdecl` anyway.  Either way the Map source call must survive.
    @Test
    func mapExtremaKeepTheirSourceCallAndNotTheMapRuntimeRewrite() throws {
        let source = """
        fun main() {
            val scores = mapOf("a" to 1, "b" to 2)
            println(scores.maxByOrNull { it.value })
            println(scores.minByOrNull { it.value })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapExtremaRouting",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            #expect(
                mainCallees.contains("maxByOrNull") && mainCallees.contains("minByOrNull"),
                "the Map source calls must survive; callees: \(mainCallees)"
            )

            let callees = Set(Self.allCallees(in: module, interner: ctx.interner))
            let redirects = callees.intersection(["kk_map_maxByOrNull", "kk_map_minByOrNull"])
            #expect(
                redirects.isEmpty,
                "Map extrema must not reach the implementation-less kk_map_* exports; got \(redirects.sorted())"
            )
        }
    }

    /// `max` / `min` / `maxOrNull` / `minOrNull` are the names
    /// `+CallRewriteSequenceTerminals.swift` compares by hand, so a `Sequence`
    /// receiver is where dropping them from the policy could have shown up.
    /// It does not: that function's entry guard bails for a source-backed
    /// symbol whose receiver is not a tracked runtime Sequence handle, and
    /// with the bundled stdlib the `sequenceOf` / `generateSequence` /
    /// `asSequence` results are not tracked.  Unlike the `kk_list_*` exports
    /// `kk_sequence_max` / `kk_sequence_min` do exist, so the failure mode here
    /// would be a silent bypass of the Kotlin implementation rather than a link
    /// error — which is why it is pinned.  RF-LOWER-CALL-014 owns the runtime
    /// representation check that would make the Sequence side principled.
    @Test
    func sequenceExtremaKeepTheirSourceCallAndNotTheSequenceTerminals() throws {
        let source = """
        fun main() {
            println(listOf(3, 1, 4).asSequence().maxOrNull())
            println(listOf(3, 1, 4).asSequence().minOrNull())
            println(listOf(3, 1, 4).asSequence().max())
            println(listOf(3, 1, 4).asSequence().min())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "SequenceExtremaRouting",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let callees = Set(Self.allCallees(in: module, interner: ctx.interner))
            #expect(
                callees.isSuperset(of: ["max", "min", "maxOrNull", "minOrNull"]),
                "the Sequence source calls must survive; callees: \(callees.sorted())"
            )

            let redirects = callees.filter {
                $0.hasPrefix("kk_sequence_max") || $0.hasPrefix("kk_sequence_min")
            }
            #expect(
                redirects.isEmpty,
                "Sequence extrema must not be diverted to kk_sequence_*; got \(redirects.sorted())"
            )
        }
    }

    /// `sorted` is the one name still listed in the virtual policy, with the
    /// KSP-453/454 Range/progression group: `+VirtualCallRewrite+Range.swift`
    /// is a real consumer of that entry.  The direct-call policy no longer
    /// lists it — nothing on that path compares against it.  Either way a
    /// range `sorted()` must keep the bundled Kotlin declaration rather than
    /// take the per-element-type `kk_*_range_sorted` export.
    @Test
    func rangeSortedKeepsItsSourceCallAndNotTheRangeRuntimeRewrite() throws {
        let source = """
        fun main() {
            println((1..5).sorted())
            println((1L..5L).sorted())
            println(('a'..'e').sorted())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "RangeSortedRouting",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            #expect(
                mainCallees.contains("sorted"),
                "the range sorted() source call must survive; callees: \(mainCallees)"
            )

            let callees = Set(Self.allCallees(in: module, interner: ctx.interner))
            let redirects = callees.filter { $0.hasSuffix("range_sorted") }
            #expect(
                redirects.isEmpty,
                "range sorted() must not be diverted to kk_*_range_sorted; got \(redirects.sorted())"
            )
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// RF-LOWER-CALL-012: pin the *production* routing of the Map `map` /
/// `filter` / `filterNot` / `mapNotNull` / `forEach` / `mapValues` /
/// `mapValuesTo` / `mapKeys` / `mapKeysTo` / `filterKeys` / `filterValues` /
/// `flatMap` / `any` / `all` / `none` family.
///
/// KSP-430 moved these APIs to `Stdlib/kotlin/collections/MapHOF.kt`, and
/// `Sources/Runtime` has no `@_cdecl` left for any `kk_map_map` /
/// `kk_map_filter` / `kk_map_forEach` / `kk_map_mapValues` / `kk_map_mapKeys`
/// / `kk_map_filterKeys` / `kk_map_filterValues` / `kk_map_flatMap` /
/// `kk_map_any` / `kk_map_all` / `kk_map_none` / `kk_map_maxByOrNull` /
/// `kk_map_minByOrNull` — only `Tests/RuntimeTests/RuntimeCollectionHOF430MapShims.swift`
/// still declares them, as test doubles. A lowering rewrite that redirected a
/// resolved Kotlin declaration to one of those names would therefore not fail
/// a Core test — it would fail at link time. Nothing pinned that before this
/// suite.
///
/// RF-LOWER-CALL-012 found the Map-receiver branches in
/// `+CallRewriteHOFCore.swift`, `+CallRewriteHandlers.swift`
/// (`rewriteCollectionHOFCall`'s Map arm plus `mapHOFRuntimeName` /
/// `mapHOFReturnsList` / `mapHOFReturnsMap`) and
/// `+VirtualCallRewrite.swift` (`rewriteMapHOF`) to be unreachable: every one
/// of these names, once resolved to the bundled `MapHOF.kt` declaration, is
/// short-circuited by `shouldPreserveSourceBackedAggregateCall` /
/// `shouldPreserveSourceBackedVirtualCall` before the dispatcher that owned
/// those branches ever ran, and removing all three branches left post-lowering
/// KIR byte-identical (checked with `--emit kir` on both the
/// `--stdlib-from-source` and default-artifact stdlib paths, plus an
/// executable run, for every name below). These tests are what keeps that
/// from regressing: they assert the routing directly rather than the
/// presence of a name in an allowlist.
///
/// `maxByOrNull` / `minByOrNull` are already pinned by
/// `ListSortExtremaLoweringRoutingTests.mapExtremaKeepTheirSourceCallAndNotTheMapRuntimeRewrite`
/// (they are shared with the List sort/extrema group that test suite owns),
/// so this suite does not duplicate them.
@Suite
struct MapHOFLoweringRoutingTests {
    /// The `kk_map_*` names the deleted `mapHOFRuntimeName` switch in
    /// `+CallRewriteHandlers.swift` used to produce. None has a `@_cdecl` in
    /// `Sources/Runtime` any more.
    static let legacyMapHOFRuntimeCallees: Set<String> = [
        "kk_map_map", "kk_map_filter", "kk_map_forEach",
        "kk_map_mapValues", "kk_map_mapKeys",
        "kk_map_filterKeys", "kk_map_filterValues",
        "kk_map_flatMap", "kk_map_any", "kk_map_all", "kk_map_none",
        "kk_map_maxByOrNull", "kk_map_minByOrNull",
    ]

    /// Every name the removed Map branches used to match, exercised on a
    /// `Map` receiver. `mapValuesTo` / `mapKeysTo` / `filterNot` /
    /// `mapNotNull` were never in the deleted `mapHOFRuntimeName` switch (so
    /// they have no corresponding `legacyMapHOFRuntimeCallees` entry), but
    /// they shared the same dead outer gates and are worth pinning too.
    static let expectedSourceCallees: Set<String> = [
        "map", "filter", "filterNot", "mapNotNull", "forEach",
        "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo",
        "filterKeys", "filterValues", "flatMap",
        "any", "all", "none",
    ]

    static let mapHOFSource = """
    fun main() {
        val m: Map<String, Int> = mapOf("a" to 1, "b" to 2, "c" to 3)
        println(m.map { it.value })
        println(m.filter { it.value > 1 })
        println(m.filterNot { it.value > 1 })
        println(m.mapNotNull { if (it.value > 1) it.value else null })
        m.forEach { println(it.key) }
        println(m.mapValues { it.value * 2 })
        val destValues = mutableMapOf<String, Int>()
        m.mapValuesTo(destValues) { it.value * 3 }
        println(destValues)
        println(m.mapKeys { it.key + "!" })
        val destKeys = mutableMapOf<String, Int>()
        m.mapKeysTo(destKeys) { it.key + "?" }
        println(destKeys)
        println(m.filterKeys { it != "a" })
        println(m.filterValues { it != 1 })
        println(m.flatMap { listOf(it.value, it.value) })
        println(m.any { it.value > 2 })
        println(m.all { it.value > 0 })
        println(m.none { it.value < 0 })
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

    /// `.call` / `.virtualCall` callees across *every* function in the
    /// module, not just `main`: a rewrite that fired inside an injected
    /// stdlib body would otherwise go unnoticed.
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

    /// The calls in `body` whose callee is one of the Map HOF names, with the
    /// symbol the frontend resolved them to.
    static func mapHOFCalls(
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

    /// All 15 names survive `CollectionLiteralLoweringPass` as resolved
    /// source calls, and no legacy `kk_map_*` name reaches the lowered
    /// module.
    @Test
    func sourceBackedMapHOFCallsSurviveCollectionLiteralLowering() throws {
        try withTemporaryFile(contents: Self.mapHOFSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapHOFRouting",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let survivors = Set(Self.mapHOFCalls(in: body, interner: ctx.interner).map(\.name))
            let missing = Self.expectedSourceCallees.subtracting(survivors).sorted()
            #expect(
                survivors == Self.expectedSourceCallees,
                "every Map HOF call must stay a source call; missing: \(missing)"
            )

            let callees = Set(Self.allCallees(in: module, interner: ctx.interner))
            let redirects = callees.intersection(Self.legacyMapHOFRuntimeCallees)
            #expect(
                redirects.isEmpty,
                "no legacy kk_map_* HOF rewrite may reach lowered KIR; got \(redirects.sorted())"
            )
        }
    }

    /// Why the rewrite must not fire: each name resolves to a non-synthetic,
    /// source-backed declaration in the bundled Kotlin stdlib with no
    /// `externalLinkName` to bridge through.
    @Test
    func mapHOFCalleesResolveToBundledKotlinSource() throws {
        try withTemporaryFile(contents: Self.mapHOFSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapHOFSymbols",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let calls = Self.mapHOFCalls(in: body, interner: ctx.interner)
            #expect(calls.count == Self.expectedSourceCallees.count, "expected \(Self.expectedSourceCallees.count) Map HOF calls; got \(calls.count)")

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
    /// `Map` receiver, which is what the policy keys off — must be left
    /// alone and must never pick up a `kk_map_*` callee.
    @Test
    func userDefinedMapHOFNamedFunctionsAreNotRewritten() throws {
        let source = """
        fun Map<String, Int>.filterKeys(marker: Int): Int = marker + size

        fun Map<String, Int>.mapValues(marker: String): String = marker + size

        fun main() {
            val m = mapOf("a" to 1, "b" to 2)
            println(m.filterKeys(1))
            println(m.mapValues("m"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapHOFShadowing",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            #expect(mainCallees.contains("filterKeys"), "the user filterKeys must stay; callees: \(mainCallees)")
            #expect(mainCallees.contains("mapValues"), "the user mapValues must stay; callees: \(mainCallees)")

            let callees = Set(Self.allCallees(in: module, interner: ctx.interner))
            #expect(
                callees.intersection(Self.legacyMapHOFRuntimeCallees).isEmpty,
                "a user function may never be rewritten to a runtime bridge; callees: \(callees.sorted())"
            )
        }
    }

    // MARK: - the removed virtual-dispatch branch never fired

    /// `rewriteMapHOF` in `+VirtualCallRewrite.swift` matched a `.virtualCall`
    /// with a Map HOF callee, but Map HOF names are bundled Kotlin extension
    /// functions, so Sema always resolves a call to them statically:
    /// CallLowerer never emits `.virtualCall` for these names, only `.call`
    /// — even when the *receiver* is reached through genuine virtual
    /// dispatch (an interface property, an abstract-class method). This
    /// source forces both of those (`HasMap.data` reads through an itable,
    /// `AbstractHolder.useIt` through a vtable), confirmed by the presence of
    /// `.virtualCall` instructions for `get`/`useIt` below, while the Map HOF
    /// calls on the result stay direct.
    @Test
    func mapHOFCallsStayDirectCallsThroughVirtualDispatchedReceivers() throws {
        let source = """
        interface HasMap {
            val data: Map<String, Int>
        }
        class Impl(override val data: Map<String, Int>) : HasMap

        abstract class AbstractHolder {
            abstract val data: Map<String, Int>
            fun useIt(): Int {
                return data.mapValues { it.value + 1 }.filterKeys { it.isNotEmpty() }.size
            }
        }
        class ConcreteHolder(override val data: Map<String, Int>) : AbstractHolder()

        fun useInterface(h: HasMap): Int {
            return h.data.mapValues { it.value + 1 }.filterKeys { it.isNotEmpty() }.size
        }

        fun main() {
            val m: Map<String, Int> = mapOf("a" to 1, "b" to 2)
            val impl: HasMap = Impl(m)
            println(useInterface(impl))
            val holder: AbstractHolder = ConcreteHolder(m)
            println(holder.useIt())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapHOFVirtualDispatch",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let virtualCallees = Set(findAllKIRFunctions(in: module).flatMap {
                extractVirtualCallees(from: $0.body, interner: ctx.interner)
            })
            #expect(
                !virtualCallees.isEmpty,
                "the source must actually exercise virtual dispatch (interface property / abstract method); got none"
            )
            #expect(
                virtualCallees.isDisjoint(with: ["mapValues", "filterKeys"]),
                "Map HOF names must never be dispatched as a virtualCall; got \(virtualCallees.sorted())"
            )

            let allCallees = Set(Self.allCallees(in: module, interner: ctx.interner))
            #expect(
                allCallees.isSuperset(of: ["mapValues", "filterKeys"]),
                "the Map HOF source calls must survive as direct calls; callees: \(allCallees.sorted())"
            )
            let redirects = allCallees.intersection(Self.legacyMapHOFRuntimeCallees)
            #expect(
                redirects.isEmpty,
                "no legacy kk_map_* HOF rewrite may reach lowered KIR; got \(redirects.sorted())"
            )
        }
    }
}
#endif

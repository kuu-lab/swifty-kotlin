#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// RF-LOWER-CALL-012: pin the *production* routing of the Map-exclusive
/// higher-order functions — `mapValues` / `mapValuesTo` / `mapKeys` /
/// `mapKeysTo` / `filterKeys` / `filterValues` — before the residual
/// `kk_map_*` rewrites in `CollectionLiteralLoweringPass` are removed.
///
/// These six names are the only Map HOFs with no List / Set / Sequence
/// counterpart, so they can be reasoned about without touching the shared
/// `map` / `filter` / `forEach` / `flatMap` rewrites owned by
/// RF-LOWER-CALL-008/010/014.
///
/// Two independent facts make the rewrites unreachable in production, and both
/// are asserted below so a regression shows up as a failing test rather than
/// as a silently resurrected runtime bridge:
///
///  1. `MapHOF.kt` declares all six as bundled Kotlin extensions, so the
///     resolved symbol is source-backed and
///     `shouldPreserveSourceBackedAggregateCall` appends the call untouched.
///  2. `StdlibSurfaceSpec.mapHOFMembers` is empty (KSP-430) and `Sources/Runtime`
///     exports no `kk_map_mapValues` / `kk_map_mapKeys` / `kk_map_filterKeys` /
///     `kk_map_filterValues` / `kk_map_mapKeysTo` / `kk_map_mapValuesTo`
///     `@_cdecl` — the only definitions live in `Tests/RuntimeTests`. A rewrite
///     that did fire would emit a call that cannot link.
///
/// The result classification (`mapValues` on a Map yields a Map) is carried by
/// `CollectionLiteralLoweringPass+PreScan.swift`, not by the rewrite, so it
/// survives the removal; `mapResultStaysClassifiedAsMap` pins that.
@Suite
struct MapHOFLoweringRoutingTests {
    /// The residual runtime entry points the rewrites substituted. Matched
    /// exactly — `kk_map_size` / `kk_map_get` and friends are live Map
    /// accessors and must keep appearing.
    private static let residualMapHOFRuntimeCallees: Set<String> = [
        "kk_map_mapValues", "kk_map_mapValuesTo",
        "kk_map_mapKeys", "kk_map_mapKeysTo",
        "kk_map_filterKeys", "kk_map_filterValues",
    ]

    /// The Map-exclusive HOF names. Deliberately excludes `map` / `filter` /
    /// `filterNot` / `forEach` / `flatMap` / `any` / `all` / `none`, whose
    /// rewrites still serve List and Sequence receivers.
    private static let mapExclusiveHOFNames = [
        "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo",
        "filterKeys", "filterValues",
    ]

    private static let mapHOFSource = """
    fun main() {
        val m = mapOf("a" to 1, "bb" to 2, "ccc" to 3)
        val values = m.mapValues { it.value * 10 }
        val keys = m.mapKeys { it.key.length }
        val byKey = m.filterKeys { it != "a" }
        val byValue = m.filterValues { it > 1 }
        val keyDestination = m.mapKeysTo(mutableMapOf<Int, Int>()) { it.key.length }
        val valueDestination = m.mapValuesTo(mutableMapOf<String, String>()) { it.value.toString() }
        println(values)
        println(keys)
        println(byKey)
        println(byValue)
        println(keyDestination)
        println(valueDestination)
    }
    """

    /// Every `.call` in `body` whose callee is one of the six Map-exclusive HOF
    /// names, paired with its argument count and resolved symbol.
    private static func mapHOFCalls(
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [(name: String, argumentCount: Int, symbol: SymbolID?)] {
        body.compactMap { instruction in
            guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction else { return nil }
            let name = interner.resolve(callee)
            guard mapExclusiveHOFNames.contains(name) else { return nil }
            return (name, arguments.count, symbol)
        }
    }

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

    // MARK: - source-backed routing (the production path)

    /// All six Map-exclusive HOFs survive `CollectionLiteralLoweringPass`
    /// untouched, so the bundled `MapHOF.kt` body is what the backend inlines.
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
            let callees = extractCallees(from: body, interner: ctx.interner)
            let survivors = Set(Self.mapHOFCalls(in: body, interner: ctx.interner).map(\.name))

            #expect(
                survivors == Set(Self.mapExclusiveHOFNames),
                "every Map-exclusive HOF must stay a source call; got: \(survivors.sorted())"
            )
            #expect(
                callees.allSatisfy { !Self.residualMapHOFRuntimeCallees.contains($0) },
                "no kk_map_* Map-HOF rewrite may reach production KIR; callees: \(callees)"
            )
        }
    }

    /// The reason the rewrites are skipped: the resolved callee is a
    /// non-synthetic, source-backed `MapHOF.kt` declaration with no
    /// `externalLinkName`, so `shouldPreserveSourceBackedAggregateCall`
    /// short-circuits before any Map rewrite is consulted.
    @Test
    func sourceBackedMapHOFCalleesResolveToBundledMapHOF() throws {
        try withTemporaryFile(contents: Self.mapHOFSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapHOFRoutingSymbols",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mapHOFCalls = Self.mapHOFCalls(in: body, interner: ctx.interner)
            #expect(
                mapHOFCalls.count == Self.mapExclusiveHOFNames.count,
                "expected six Map-exclusive HOF calls; got \(mapHOFCalls.count)"
            )

            let sema = try #require(ctx.sema)
            for call in mapHOFCalls {
                let label = "\(call.name)/\(call.argumentCount)"
                let symbolID = try #require(call.symbol, "\(label): production KIR must carry a resolved symbol")
                let symbol = try #require(sema.symbols.symbol(symbolID), "\(label): symbol must be in the table")

                #expect(!symbol.flags.contains(.synthetic), "\(label) must not resolve to a synthetic stub")
                #expect(
                    sema.symbols.externalLinkName(for: symbolID) == nil,
                    "\(label) must not carry an external link name"
                )
                #expect(sema.symbols.isSourceBackedSymbol(symbolID), "\(label) must be source-backed")

                let fileID = try #require(sema.symbols.sourceFileID(for: symbolID), "\(label): missing source file")
                #expect(
                    ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/MapHOF.kt",
                    "\(label) must resolve to MapHOF.kt; got \(String(describing: ctx.sourceManager.path(of: fileID)))"
                )
            }
        }
    }

    /// `HeaderHelpers+SyntheticMapStubs` still registers `kk_map_*`-linked
    /// members for these names when the bundled stdlib is absent. With the
    /// stdlib present the bundled declarations must win, so no synthetic
    /// `kotlin.collections.Map` member is left for overload resolution to pick
    /// — otherwise the preserve check would see a non-source-backed symbol.
    @Test
    func noSyntheticMapHOFOverloadSurvivesAlongsideBundledStdlib() throws {
        try withTemporaryFile(contents: Self.mapHOFSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapHOFRoutingStubs",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let mapFQName = ["kotlin", "collections", "Map"].map(ctx.interner.intern)
            for name in Self.mapExclusiveHOFNames {
                let syntheticOverloads = sema.symbols
                    .lookupAll(fqName: mapFQName + [ctx.interner.intern(name)])
                    .filter { sema.symbols.symbol($0)?.flags.contains(.synthetic) == true }
                #expect(
                    syntheticOverloads.isEmpty,
                    "Map.\(name) must have no synthetic overload alongside the bundled stdlib"
                )
            }
        }
    }

    /// The Map / List classification of a HOF result is produced by PreScan,
    /// independent of the rewrite that also used to tag it. A Map-returning
    /// HOF result must still reach the Map accessor rewrites, and a
    /// List-returning one must not.
    @Test
    func mapResultStaysClassifiedAsMap() throws {
        let source = """
        fun main() {
            val m = mapOf("a" to 1, "bb" to 2)
            val values = m.mapValues { it.value * 10 }
            val byKey = m.filterKeys { it != "a" }
            println(values.size)
            println(byKey["bb"])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapHOFResultClassification",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_map_size"),
                "mapValues result must stay Map-classified so .size lowers to kk_map_size; callees: \(callees)"
            )
            #expect(
                callees.contains("__kk_map_get"),
                "filterKeys result must stay Map-classified so [] lowers to __kk_map_get; callees: \(callees)"
            )
            #expect(
                callees.allSatisfy { !Self.residualMapHOFRuntimeCallees.contains($0) },
                "classification must not come from a kk_map_* HOF rewrite; callees: \(callees)"
            )
        }
    }

    /// User functions that merely share the Map HOF names must be left alone:
    /// `isSourceBackedSymbol` is true for any declaration with a `declSite`,
    /// so the preserve check already protects them — and after the residual
    /// rewrites are gone there is nothing left that could claim the name.
    @Test
    func userDefinedMapHOFNamedFunctionsAreNotRewritten() throws {
        let source = """
        fun Map<String, Int>.mapValues(scale: Int): Int {
            var total = 0
            for (entry in this.entries) { total += entry.value * scale }
            return total
        }

        fun Map<String, Int>.filterKeys(prefix: String, drop: Boolean): Int {
            var count = 0
            for (entry in this.entries) {
                if (entry.key.startsWith(prefix) != drop) count += 1
            }
            return count
        }

        fun main() {
            val m = mapOf("a" to 1, "bb" to 2)
            println(m.mapValues(3))
            println(m.filterKeys("a", false))
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
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("mapValues"), "the user mapValues must stay; callees: \(callees)")
            #expect(callees.contains("filterKeys"), "the user filterKeys must stay; callees: \(callees)")
            #expect(
                callees.allSatisfy { !Self.residualMapHOFRuntimeCallees.contains($0) },
                "a user function may never be rewritten to a runtime Map HOF; callees: \(callees)"
            )
        }
    }
}
#endif

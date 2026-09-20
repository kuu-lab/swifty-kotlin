#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// RF-LOWER-CALL-012 follow-up: pin the routing of `Map<K, V>.count(predicate)`.
///
/// `Stdlib/kotlin/collections/MapHOF.kt` declares
/// `Map<K, V>.count(predicate: (Map.Entry<K, V>) -> Boolean): Int`, but
/// `CollectionLiteralLoweringPass+CallRewriteFactories.swift` still carried a
/// `map.count(predicate)` -> `kk_map_count` rewrite branch. It was
/// unreachable — the historical synthetic Map registration path skipped the
/// competing
/// synthetic `count` member whenever `bundledIndex.contains(ownerFQName:
/// mapFQName, name: "count", arity: 1)` is true, which it always is once
/// KSP-430 bundled `MapHOF.kt`, so a resolved `count(predicate)` call on a
/// Map receiver can only ever be `.sourceBacked` — and the branch's own
/// inline `isSourceBackedBundledFunction` guard existed for exactly that
/// resolution, unlike the sibling Map HOF branches CALL-012 removed, which
/// relied entirely on the source-backed preservation gate running
/// first. This branch instead sits inside `rewriteFactoryAndBuilderCall`,
/// which `lowerCallInstruction` calls *before* that later check, so it had
/// to carry its own resolution test — one that was always false for a call
/// that reached it with a real symbol. `kk_map_count` has no `@_cdecl` in
/// `Sources/Runtime`, only a `Tests/RuntimeTests/RuntimeCollectionHOF430MapShims.swift`
/// test shim, the same pattern as the thirteen `kk_map_*` targets CALL-012
/// found dead.
@Suite
struct MapCountLoweringRoutingTests {
    private static let mapCountSource = """
    fun main() {
        val m = mapOf("a" to 1, "b" to 2, "c" to 3)
        println(m.count { it.value > 1 })

        val hm = hashMapOf("a" to 1, "b" to 2, "c" to 3)
        println(hm.count { it.value > 1 })

        val mm = mutableMapOf("a" to 1, "b" to 2)
        println(mm.count { it.value > 1 })

        val chained = mapOf("a" to 1, "b" to 2, "c" to 3).filterValues { it > 1 }
        println(chained.count { it.value > 1 })

        val asInterface: Map<String, Int> = mapOf("a" to 1, "b" to 2)
        println(asInterface.count { it.value > 1 })
    }
    """

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

    /// `.call` instructions whose callee resolves to `"count"`, with the
    /// resolved symbol and argument count (receiver + lambda [+ closure word]).
    private static func countCalls(
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [(argumentCount: Int, symbol: SymbolID?)] {
        body.compactMap { instruction in
            guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction,
                  interner.resolve(callee) == "count"
            else { return nil }
            return (arguments.count, symbol)
        }
    }

    /// Every `Map.count(predicate)` call — on a read-only map, a `HashMap`, a
    /// `MutableMap`, a chained rewrite result, and an interface-typed
    /// variable — stays a resolved source call, and `kk_map_count` never
    /// reaches lowered KIR.
    @Test
    func mapCountPredicateSurvivesAsSourceCallOnEveryMapReceiverShape() throws {
        try withTemporaryFile(contents: Self.mapCountSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapCountRouting",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try Self.runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let countCalls = Self.countCalls(in: body, interner: ctx.interner)
            #expect(countCalls.count == 5, "expected 5 count(predicate) calls; got \(countCalls.count)")
            for call in countCalls {
                #expect(call.symbol != nil, "every Map.count(predicate) call must carry a resolved symbol")
            }

            let callees = Set(extractCallees(from: body, interner: ctx.interner))
            #expect(
                !callees.contains("kk_map_count"),
                "kk_map_count has no @_cdecl in Sources/Runtime and must never be emitted; callees: \(callees.sorted())"
            )

            // The exact shape the deleted rewrite branch produced: a
            // `symbol: nil` call to the bare name "count" with the receiver,
            // lambda and closure word (3 arguments). Guards against a future
            // rewrite being re-added without checking reachability first.
            let brokenCountRewrites = body.filter { instruction in
                guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction else { return false }
                return symbol == nil
                    && ctx.interner.resolve(callee) == "count"
                    && arguments.count == 3
            }
            #expect(
                brokenCountRewrites.isEmpty,
                "the legacy Map count(predicate) rewrite must stay deleted; found \(brokenCountRewrites.count)"
            )
        }
    }

    /// The reason no rewrite fires: every resolved `count(predicate)` callee
    /// is source-backed in `MapHOF.kt`, so `isSourceBackedBundledFunction`
    /// (had it stayed) would always have declined the rewrite.
    @Test
    func mapCountPredicateCalleesResolveToMapHOF() throws {
        try withTemporaryFile(contents: Self.mapCountSource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MapCountRoutingSymbols",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let countCalls = Self.countCalls(in: body, interner: ctx.interner)
            #expect(countCalls.count == 5, "expected 5 count(predicate) calls; got \(countCalls.count)")

            let sema = try #require(ctx.sema)
            for call in countCalls {
                let symbolID = try #require(call.symbol, "every count(predicate) call must resolve to a symbol")
                #expect(sema.symbols.isSourceBackedSymbol(symbolID), "count(predicate) must be source-backed")

                let fileID = try #require(sema.symbols.sourceFileID(for: symbolID), "missing source file")
                #expect(
                    ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/MapHOF.kt",
                    "count(predicate) must resolve to MapHOF.kt; got \(String(describing: ctx.sourceManager.path(of: fileID)))"
                )
            }
        }
    }
}
#endif

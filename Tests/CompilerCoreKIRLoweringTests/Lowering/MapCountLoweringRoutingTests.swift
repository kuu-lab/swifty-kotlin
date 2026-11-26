#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

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

    private static func countCalls(
        in body: [KIRInstruction],
        interner: StringInterner
    ) -> [(argumentCount: Int, symbol: SymbolID?)] {
        body.compactMap { instruction in
            guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction,
                  callee == KnownCompilerNames(interner: interner).count
            else { return nil }
            return (arguments.count, symbol)
        }
    }

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

            let module = try runCollectionLiteralPassOnly(ctx)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let countCalls = Self.countCalls(in: body, interner: ctx.interner)
            #expect(countCalls.count == 5, "expected 5 count(predicate) calls; got \(countCalls.count)")
            for call in countCalls {
                #expect(call.symbol != nil, "every Map.count(predicate) call must carry a resolved symbol")
            }

            let callees = Set(extractCallees(from: body, interner: ctx.interner))
            #expect(
                !LoweringTestRuntime.operations(in: callees).contains("map_count"),
                "The retired Map count bridge must never be emitted; callees: \(callees.sorted())"
            )

            let brokenCountRewrites = body.filter { instruction in
                guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction else { return false }
                return symbol == nil
                    && callee == KnownCompilerNames(interner: ctx.interner).count
                    && arguments.count == 3
            }
            #expect(
                brokenCountRewrites.isEmpty,
                "the legacy Map count(predicate) rewrite must stay deleted; found \(brokenCountRewrites.count)"
            )
        }
    }

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

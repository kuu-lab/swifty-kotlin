@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

@Suite(.serialized)
struct CodegenBackendCollectionIsNullOrEmptyTests {
    @Test
    func testCodegenNullableCollectionsIsNullOrEmptyUsesExpectedRouting() throws {
        let source = """
        fun main() {
            val nullableList: List<Int>? = null
            val nullableSet: Set<Int>? = null
            val nullableMap: Map<String, Int>? = null
            val nullableArray: Array<Int>? = null
            val nullableCollection: Collection<Int>? = null
            println(nullableList.isNullOrEmpty())
            println(nullableSet.isNullOrEmpty())
            println(nullableMap.isNullOrEmpty())
            println(nullableArray.isNullOrEmpty())
            println(nullableCollection.isNullOrEmpty())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            #expect(throwFlags[try runtimeABICallee("list_is_empty")]?.allSatisfy { $0 == false } == true)
            #expect(throwFlags[try runtimeABICallee("set_is_empty")]?.allSatisfy { $0 == false } == true)
            // Map.isNullOrEmpty is source-backed; after inlining it may reach the
            // Map.isEmpty ABI, but never through the symbol-less legacy bridge.
            let sema = try #require(ctx.sema)
            let mapIsEmptyCallee = try runtimeABICallee("map_is_empty")
            let mapIsEmptyCalls = body.compactMap { instruction -> (symbol: SymbolID?, canThrow: Bool)? in
                guard case let .call(symbol, callee, _, _, canThrow, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == mapIsEmptyCallee
                else {
                    return nil
                }
                return (symbol, canThrow)
            }
            #expect(!mapIsEmptyCalls.isEmpty)
            #expect(mapIsEmptyCalls.allSatisfy { call in call.symbol != nil && !call.canThrow })
            #expect(mapIsEmptyCalls.contains { call in
                guard let symbol = call.symbol,
                      let semanticSymbol = sema.symbols.symbol(symbol)
                else {
                    return false
                }
                return ctx.interner.resolve(semanticSymbol.name) == "isEmpty"
            })
            #expect(throwFlags[try runtimeABICallee("array_is_empty")]?.allSatisfy { $0 == false } == true)
            // A bare Collection<T>? receiver may hold a Set box at runtime, so
            // isNullOrEmpty must use the type-tag dispatching collection bridge
            // rather than the List-only kk_list_is_empty (KUU-543).
            #expect(throwFlags[try runtimeABICallee("collection_isEmpty")]?.allSatisfy { $0 == false } == true)
        }
    }
}
#endif

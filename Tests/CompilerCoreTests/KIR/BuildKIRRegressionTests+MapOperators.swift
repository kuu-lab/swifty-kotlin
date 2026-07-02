#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test func testMapMinusKeyLowersToMapRuntimeOperator() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
            val map2 = map - "a"
            println(map2)

            val intMap = mapOf(1 to "one", 2 to "two", 3 to "three")
            val intMap2 = intMap - 1
            println(intMap2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("kk_map_minus"), "Expected Map.minus(key) to lower to kk_map_minus, got: \(callees)")
            #expect(!callees.contains("kk_op_sub"), "Map.minus(key) must not fall back to generic subtraction, got: \(callees)")
        }
    }
}
#endif

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

            #expect(callees.contains("minus"), "Expected Map.minus(key) to lower to bundled source minus, got: \(callees)")
            #expect(!callees.contains("kk_map_minus"), "Map.minus(key) must not use legacy kk_map_minus, got: \(callees)")
            #expect(!callees.contains("kk_op_sub"), "Map.minus(key) must not fall back to generic subtraction, got: \(callees)")
        }
    }

    @Test func testMapMinusSequenceAndArrayLowerToBundledSource() throws {
        let source = """
        fun main() {
            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
            println(map - sequenceOf("a"))
            println(map - arrayOf("b"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            let sourceMinusCalls = callees.filter { $0 == "minus" }

            #expect(sourceMinusCalls.count >= 2, "Expected Sequence and Array Map.minus calls to remain source-backed, got: \(callees)")
            #expect(!callees.contains("kk_map_minus"), "Map.minus(Sequence/Array) must not use legacy kk_map_minus, got: \(callees)")
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testLocalFunctionVarargBodyAndKIRParameterTypes() throws {
        let source = """
        fun sinkInts(xs: IntArray): Int = xs.size
        fun main() {
            fun block(vararg xs: Int) {
                val a: IntArray = xs
                println(xs.sum())
                println(xs.size)
                println(xs.first())
                println(sinkInts(xs))
                println(xs[0])
                for (x in xs) println(x)
            }
            fun expression(vararg xs: Int) = xs.sum()
            fun strings(vararg xs: String): Int = xs.size
            fun nullableInts(vararg xs: Int?): Int = xs.size
            fun ordinary(xs: IntArray): Int = xs.sum()
            block(1, 2, 3)
            block(*intArrayOf(4, 5))
            println(expression(6, 7))
            println(strings("a", "b"))
            println(nullableInts(1, null))
            println(ordinary(intArrayOf(8, 9)))
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Local vararg bodies must resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let kir = try #require(ctx.kir)
        let expectedNames = ["block": "IntArray", "expression": "IntArray", "strings": "List", "nullableInts": "List", "ordinary": "IntArray"]
        var observedNames: [String: String] = [:]
        for decl in kir.arena.declarations {
            guard case let .function(function) = decl,
                  let expected = expectedNames[ctx.interner.resolve(function.name)]
            else { continue }
            let signature = try #require(sema.symbols.functionSignature(for: function.symbol))
            let parameterSymbol = try #require(signature.valueParameterSymbols.first)
            let parameter = try #require(function.params.first { $0.symbol == parameterSymbol })
            let (_, typeSymbol) = try #require(resolveClassTypeSymbol(parameter.type, sema: sema))
            let actualName = ctx.interner.resolve(typeSymbol.name)
            #expect(actualName == expected)
            observedNames[ctx.interner.resolve(function.name)] = actualName
            if signature.valueParameterIsVararg.first == true {
                #expect(signature.parameterTypes.first != parameter.type, "Call signatures must retain the element type")
            }
        }
        #expect(observedNames == expectedNames)
    }

    @Test
    func testLocalPrimitiveVarargRejectsGenericArraySink() throws {
        let ctx = makeContextFromSource("""
        fun sink(xs: Array<Int>): Int = xs.size
        fun main() {
            fun local(vararg xs: Int) { sink(xs) }
            local(1, 2)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }
}
#endif

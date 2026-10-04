#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LongLiteralOverloadResolutionTests {
    @Test func testLiteralsBindToSelectedLongParameters() throws {
        let source = """
            fun g(): Long = 0
            fun g(l: Long): Long = l
            class X {
                fun f(): Long = 0
                fun f(l: Long): Long = l
                fun f(a: Long, b: Long): Long = a + b
            }
            fun X.extension(): Long = 0
            fun X.extension(value: Long): Long = value
            fun defaulted(tag: String = "tag", value: Long): Long = value
            fun defaulted(value: String): Long = 0
            fun nullable(value: Long?): Long? = value
            fun nullable(value: String): Long? = null
            fun main() {
                g(101)
                g(l = 102)
                g(-103)
                g(+104)
                X().f(105)
                X().f(106, 107)
                X().f(b = 108, a = 109)
                X().extension(110)
                defaulted(value = 111)
                nullable(112)
            }
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for value in [101, 102, 105, 106, 107, 108, 109, 110, 111, 112] {
                let literal = try #require(firstExprID(in: ast) { _, expr in
                    if case let .intLiteral(actual, _) = expr { return actual == Int64(value) }
                    return false
                })
                #expect(sema.bindings.exprType(for: literal) == sema.types.longType)
            }
            for op in [UnaryOp.unaryMinus, .unaryPlus] {
                let unary = try #require(firstExprID(in: ast) { _, expr in
                    if case let .unaryExpr(actual, _, _) = expr { return actual == op }
                    return false
                })
                #expect(sema.bindings.exprType(for: unary) == sema.types.longType)
            }
        }
    }

    @Test func testIntOverloadRemainsPreferredForUnsuffixedLiteral() throws {
        let source = """
            fun pick(value: Int, tag: String): Int = value
            fun pick(value: Long, tag: String): Long = value
            class X {
                fun pick(value: Int): Int = value
                fun pick(value: Long): Long = value
            }
            fun main() {
                pick(201, "int")
                X().pick(202)
                pick(203L, "long")
                X().pick(204L)
            }
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for value in [201, 202] {
                let literal = try #require(firstExprID(in: ast) { _, expr in
                    if case let .intLiteral(actual, _) = expr { return actual == Int64(value) }
                    return false
                })
                #expect(sema.bindings.exprType(for: literal) == sema.types.intType)
            }
            for (index, expr) in ast.arena.exprs.enumerated() {
                let id = ExprID(rawValue: Int32(index))
                let args: [CallArgument]
                switch expr {
                case let .call(_, _, arguments, _): args = arguments
                case let .memberCall(_, _, _, arguments, _): args = arguments
                default: continue
                }
                guard let first = args.first,
                      case .longLiteral = ast.arena.expr(first.expr)
                else { continue }
                #expect(sema.bindings.exprType(for: id) == sema.types.longType)
            }
        }
    }

    @Test(arguments: [false, true])
    func testIntVariablesAreNotAdaptedEvenAfterCachedLiteralCall(useCache: Bool) throws {
        let source = """
            fun g(): Long = 0
            fun g(l: Long): Long = l
            fun main() {
                g(100)
                val value: Int = 100
                g(value)
            }
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], includeStdlib: false,
                frontendFlags: useCache ? ["sema-cache"] : []
            )
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0002" }.count == 1)
        }
    }

    @Test func testRandomNextLongAcceptsIntegerLiterals() throws {
        let source = """
            fun main() {
                val random = kotlin.random.Random(42)
                random.nextLong(100)
                random.nextLong(50, 60)
                random.nextLong(until = 100)
                random.nextLong(until = 60, from = 50)
                random.nextLong(100L)
            }
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
        }
    }
}
#endif

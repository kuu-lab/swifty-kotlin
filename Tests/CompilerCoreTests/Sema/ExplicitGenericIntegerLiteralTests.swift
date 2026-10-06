#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExplicitGenericIntegerLiteralTests {
    @Test(arguments: [false, true])
    func arrayOfLiteralsUseExplicitElementType(useCache: Bool) throws {
        let source = """
        fun main() {
            val bytes = arrayOf<Byte>(1, 2, -128, +127)
            val shorts = arrayOf<Short>(3, 4, -32768, +32767)
            val nullableBytes = arrayOf<Byte?>(5, null)
            val ints = arrayOf(6, 7)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], frontendFlags: useCache ? ["sema-cache"] : []
            )
            try runSema(ctx)
            let hasError = ctx.diagnostics.hasError
            #expect(!hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for (value, expected) in [(1, sema.types.byteType), (2, sema.types.byteType),
                                      (3, sema.types.shortType), (4, sema.types.shortType),
                                      (5, sema.types.byteType), (6, sema.types.intType),
                                      (7, sema.types.intType)] {
                let literal = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                    if case let .intLiteral(actual, _) = expr { return actual == Int64(value) }
                    return false
                })
                let actual = sema.bindings.exprType(for: literal)
                #expect(actual == expected)
            }
            for (index, expr) in ast.arena.exprs.enumerated() {
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .unaryExpr(op, operand, _) = expr,
                      case let .intLiteral(value, _) = ast.arena.expr(operand),
                      [128, 127, 32768, 32767].contains(value)
                else { continue }
                let expected = value < 200 ? sema.types.byteType : sema.types.shortType
                let actual = sema.bindings.exprType(for: exprID)
                #expect(actual == expected)
                if op == .unaryPlus {
                    let operandType = sema.bindings.exprType(for: operand)
                    #expect(operandType == expected)
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func incompatibleArgumentsRemainRejected(useCache: Bool) throws {
        let source = """
        fun main() {
            arrayOf<Byte>(1)
            arrayOf<Short>(1)
            val value: Int = 1
            arrayOf<Byte>(128)
            arrayOf<Byte>(-129)
            arrayOf<Short>(32768)
            arrayOf<Short>(-32769)
            arrayOf<Byte>(value)
            arrayOf<Short>(value)
            arrayOf<Byte>(1L)
            arrayOf<Short>(1L)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], frontendFlags: useCache ? ["sema-cache"] : []
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 8, "\(errors.map { $0.message })")
        }
    }

    @Test func explicitGenericVarargUsesMappedTypeParameter() throws {
        let source = """
        fun <A, B> choose(first: A, vararg values: B): B = values[0]
        fun main() {
            val value: Byte = choose<String, Byte>("tag", 8, 9)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let hasError = ctx.diagnostics.hasError
            #expect(!hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
        }
    }
}
#endif

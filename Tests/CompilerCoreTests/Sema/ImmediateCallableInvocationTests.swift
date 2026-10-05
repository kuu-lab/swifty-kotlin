@testable import CompilerCore
import Testing

@Suite
struct ImmediateCallableInvocationTests {
    @Test func callableArgumentsUseExpectedIntegerLiteralTypes() throws {
        let ctx = makeContextFromSource("""
        class Holder(val f: (Byte) -> Int)
        fun parity() {
            val byte: (Byte) -> Int = { 0 }
            val short: (Short) -> Int = { 0 }
            val long: (Long) -> Int = { 0 }
            val unsigned: (UShort) -> Int = { 0 }
            byte(-128)
            byte.invoke(127)
            short(-32768)
            long(1)
            unsigned(65535u)
            Holder(byte).f(-1)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func callableArgumentsDoNotCoerceNonLiteralsOrOutOfRangeValues() throws {
        let ctx = makeContextFromSource("""
        fun parity(value: Int) {
            val byte: (Byte) -> Int = { 0 }
            byte(128)
            byte(-129)
            byte(value)
            byte(1L)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.count == 4)
    }

    @Test(arguments: [
        "fun main() { val value: Int = with(1) { { 2 } }() }",
        "val value: Int = with(1) { { 2 } }()",
        "fun value(): Int = with(1) { { 2 } }()",
    ])
    func trailingLambdaInvocationIsPreservedInDeclaration(source: String) throws {
        let (ast, _) = try buildASTModule(from: source, includeStdlib: false)
        let invocations = ast.arena.exprs.filter { expr in
            guard case let .call(callee, _, args, _) = expr,
                  args.isEmpty,
                  case let .call(_, _, innerArgs, _) = ast.arena.expr(callee)
            else {
                return false
            }
            return innerArgs.count == 2
        }
        #expect(invocations.count == 1)
    }

    @Test func parenthesizedExpressionOnNextLineRemainsSeparate() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun main() {
            val value = with(1) { 2 }
            (3)
        }
        """, includeStdlib: false)
        let main = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = main.body else {
            Issue.record("Expected a block body")
            return
        }
        #expect(statements.count == 2)
        guard case .intLiteral(3, _) = ast.arena.expr(try #require(statements.last)) else {
            Issue.record("Expected the next-line expression to remain a separate statement")
            return
        }
    }

    @Test func genericCallReturningLambdaDoesNotReceiveInvocationResultType() throws {
        let ctx = makeContextFromSources([
            """
            fun main() {
                val value: Int = with(1) { { 2 } }()
                println(value)
            }
            """
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let main = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = main.body,
              let declaration = statements.first,
              case let .localDecl(_, _, _, initializer?, _, _) = ast.arena.expr(declaration),
              case let .call(callee, _, args, _) = ast.arena.expr(initializer),
              case .call = ast.arena.expr(callee)
        else {
            Issue.record("Expected a local initializer invoking the result of with")
            return
        }
        #expect(args.isEmpty)
        #expect(sema.bindings.exprType(for: initializer) == sema.types.intType)
        let calleeType = try #require(sema.bindings.exprType(for: callee))
        guard case let .functionType(functionType) = sema.types.kind(of: calleeType) else {
            Issue.record("Expected with to return a function value")
            return
        }
        #expect(functionType.params.isEmpty)
        #expect(functionType.returnType == sema.types.intType)
    }

    @Test func immediateInvocationInGenericAndDeclarationContexts() throws {
        let ctx = makeContextFromSources([
            """
            fun <T> identity(value: T): T = value
            val topLevel: Int = with(1) { { 3 } }()
            fun expressionBody(): Int = with(1) { { 4 } }()
            fun main() {
                val withArgument: Int = with(1) { { x: Int -> x + 1 } }(6)
                val identityResult: Int = identity { 5 }()
                val runResult: Int = run { { 6 } }()
                val memberResult: Int = 1.let { { 7 } }()
                val stored: () -> Int = with(1) { { 8 } }
                val storedResult: Int = stored()
                val nonFunction: Int = with(1) { 9 }
                val direct: Int = { 10 }()
            }
            """
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func invocationResultStillMustMatchExpectedType() throws {
        let ctx = makeContextFromSources([
            """
            fun main() {
                val value: String = with(1) { { 2 } }()
            }
            """
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}

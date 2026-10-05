#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Regression coverage for value parameters whose default value expression
/// contains a `{`, e.g. a scope-function call (`run { ... }`) or a lambda
/// literal (`{ ... }`) used directly as the default. `declarationValueParameters`
/// (BuildASTPhase+DeclBuilders.swift) used to break out of its parameter-scanning
/// loop on ANY `{` token, regardless of nesting depth, mistaking the default
/// value's brace for the start of the function body. That silently truncated
/// the parameter list before its closing `)`, dropping the parameter under
/// scan and any parameters declared after it.
@Suite
struct BraceInDefaultValueParameterTests {
    @Test
    func multilineScopeFunctionDefaultPreservesLambdaAndFollowingParameter() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun f(x: Int = run {
            var count = 0
            count = count + 1
            count
        }, y: Int = 2): Int = x + y
        """, includeStdlib: false)
        let funDecl = try #require(firstFunDecl(named: "f", in: ast, interner: ctx.interner))

        #expect(ctx.diagnostics.diagnostics.isEmpty)
        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["x", "y"])
        #expect(funDecl.valueParams.allSatisfy { $0.hasDefaultValue })
        let defaultValue = try #require(funDecl.valueParams.first?.defaultValue)
        guard case let .call(_, _, args, _) = ast.arena.expr(defaultValue),
              let lambda = args.first?.expr,
              case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(lambda),
              case let .blockExpr(statements, trailingExpr, _) = ast.arena.expr(body)
        else {
            Issue.record("Expected a scope-function call with a block lambda")
            return
        }
        #expect(statements.count == 2)
        let result = try #require(trailingExpr)
        guard case let .nameRef(name, _) = ast.arena.expr(result) else {
            Issue.record("Expected the lambda to return count")
            return
        }
        #expect(ctx.interner.resolve(name) == "count")
    }

    @Test
    func testScopeFunctionDefaultValueDoesNotTruncateParameterList() throws {
        let (ast, ctx) = try buildASTModule(from: """
        package demo
        fun f(x: Int = run { 5 }): Int = x
        """, includeStdlib: false)
        let funDecl = try #require(firstFunDecl(named: "f", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["x"])
        #expect(funDecl.valueParams.first?.hasDefaultValue == true)
    }

    @Test
    func testLambdaLiteralDefaultValueDoesNotTruncateParameterList() throws {
        let (ast, ctx) = try buildASTModule(from: """
        package demo
        fun g(action: () -> Int = { 42 }): Int = action()
        """, includeStdlib: false)
        let funDecl = try #require(firstFunDecl(named: "g", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["action"])
        #expect(funDecl.valueParams.first?.hasDefaultValue == true)
    }

    @Test
    func testParameterAfterBraceContainingDefaultIsNotDropped() throws {
        let (ast, ctx) = try buildASTModule(from: """
        package demo
        fun h(x: Int = run { 1 }, y: Int = 2): Int = x + y
        """, includeStdlib: false)
        let funDecl = try #require(firstFunDecl(named: "h", in: ast, interner: ctx.interner))

        #expect(funDecl.valueParams.map { ctx.interner.resolve($0.name) } == ["x", "y"])
        #expect(funDecl.valueParams.allSatisfy { $0.hasDefaultValue })
    }

    @Test
    func testDefaultLambdaPreservesSemicolonStatementBoundaries() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun f(value: Int = run { var count = 0; count = count + 1; count }, tail: Int = 2): Int = value + tail
        """, includeStdlib: false)
        let function = try #require(firstFunDecl(named: "f", in: ast, interner: ctx.interner))
        #expect(function.valueParams.count == 2)
        let defaultExpr = try #require(function.valueParams.first?.defaultValue)
        guard case let .call(_, _, args, _) = ast.arena.expr(defaultExpr),
              let lambda = args.last,
              case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(lambda.expr),
              case let .blockExpr(statements, trailingExpr, _) = ast.arena.expr(body)
        else {
            Issue.record("Expected a run lambda with a block body")
            return
        }
        #expect(statements.count == 2)
        let trailing = try #require(trailingExpr)
        guard case let .nameRef(name, _) = ast.arena.expr(trailing) else {
            Issue.record("Expected the lambda's trailing count reference")
            return
        }
        #expect(ctx.interner.resolve(name) == "count")
    }
}
#endif

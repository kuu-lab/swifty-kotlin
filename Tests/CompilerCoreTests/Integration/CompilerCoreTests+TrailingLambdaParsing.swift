#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {
    @Test func testTrailingLambdaWithoutParensParsesAsCallExpression() throws {
        let source = """
        fun apply(block: () -> Int): Int = block()
        fun main(): Int = apply { 42 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case let .call(calleeID, _, args, _) = expr
        else {
            Issue.record("Expected trailing lambda call to parse as call expression.")
            return
        }

        #expect(args.count == 1)
        guard let calleeExpr = ast.arena.expr(calleeID),
              case let .nameRef(calleeName, _) = calleeExpr
        else {
            Issue.record("Expected call callee to be a name reference.")
            return
        }
        #expect(ctx.interner.resolve(calleeName) == "apply")

        guard let lambdaExpr = ast.arena.expr(args[0].expr),
              case .lambdaLiteral = lambdaExpr
        else {
            Issue.record("Expected trailing lambda argument.")
            return
        }
    }

    @Test func testTrailingLambdaWithExplicitTypeArgsParsesAsCallExpression() throws {
        let source = """
        fun <T> build(block: () -> T): T = block()
        fun main(): Int = build<Int> { 1 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case let .call(_, typeArgs, args, _) = expr
        else {
            Issue.record("Expected generic trailing lambda call to parse as call expression.")
            return
        }

        #expect(typeArgs.count == 1)
        #expect(args.count == 1)
    }

    @Test func testTrailingLambdaWithMultipleStatementsParsesAsLambdaBlockBody() throws {
        let source = """
        fun main() {
            val s = buildString {
                append("hello ")
                append("world")
            }
            println(s)
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = function.body,
              let localDeclID = statements.first,
              let localDeclExpr = ast.arena.expr(localDeclID),
              case let .localDecl(_, _, _, initializer, _, _) = localDeclExpr,
              let callExprID = initializer,
              let callExpr = ast.arena.expr(callExprID),
              case let .call(_, _, args, _) = callExpr,
              let lambdaArg = args.first,
              let lambdaExpr = ast.arena.expr(lambdaArg.expr),
              case let .lambdaLiteral(_, lambdaBodyID, _, _) = lambdaExpr,
              let lambdaBody = ast.arena.expr(lambdaBodyID),
              case let .blockExpr(bodyStatements, trailingExpr, _) = lambdaBody
        else {
            Issue.record("Expected builder trailing lambda body to be parsed as block expression.")
            return
        }

        #expect(bodyStatements.count == 1)
        let firstStmtID = try #require(bodyStatements.first)
        let trailingID = try #require(trailingExpr)
        guard let firstStmt = ast.arena.expr(firstStmtID), case .call = firstStmt else {
            Issue.record("Expected first lambda statement to be a call expression.")
            return
        }
        guard let trailing = ast.arena.expr(trailingID), case .call = trailing else {
            Issue.record("Expected trailing lambda expression to be a call expression.")
            return
        }
    }

    @Test func testMemberTrailingLambdaWithTwoParametersParsesBothParameters() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            val total = values.fold(0) { acc, value -> acc + value }
            println(total)
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = function.body,
              statements.count >= 2,
              let localDeclExpr = ast.arena.expr(statements[1]),
              case let .localDecl(_, _, _, initializer, _, _) = localDeclExpr,
              let callExprID = initializer,
              let callExpr = ast.arena.expr(callExprID),
              case let .memberCall(_, calleeName, _, args, _) = callExpr,
              ctx.interner.resolve(calleeName) == "fold",
              args.count == 2,
              let lambdaExpr = ast.arena.expr(args[1].expr),
              case let .lambdaLiteral(params, bodyExprID, _, _) = lambdaExpr,
              let bodyExpr = ast.arena.expr(bodyExprID)
        else {
            Issue.record("Expected fold call with trailing lambda argument.")
            return
        }

        #expect(params.map(ctx.interner.resolve) == ["acc", "value"])
        guard case .binary = bodyExpr else {
            Issue.record("Expected lambda body to parse as a binary expression.")
            return
        }
    }

    @Test func testParenthesizedCallWithTwoLambdaArgumentsParsesBothArguments() throws {
        let source = """
        fun foo(a: () -> Int, b: () -> String): Int = 0
        fun main(): Int = foo({ 42 }, { "x" })
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let function = try #require(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case let .call(calleeID, _, args, _) = expr
        else {
            Issue.record("Expected parenthesized lambda call to parse as a call expression.")
            return
        }

        guard args.count == 2 else {
            Issue.record("Expected two lambda arguments, got \(args.count).")
            return
        }
        guard let calleeExpr = ast.arena.expr(calleeID),
              case let .nameRef(calleeName, _) = calleeExpr
        else {
            Issue.record("Expected call callee to be a name reference.")
            return
        }
        #expect(ctx.interner.resolve(calleeName) == "foo")

        guard let firstArgExpr = ast.arena.expr(args[0].expr),
              case .lambdaLiteral = firstArgExpr
        else {
            Issue.record("Expected first argument to be a lambda literal.")
            return
        }

        guard let secondArgExpr = ast.arena.expr(args[1].expr),
              case .lambdaLiteral = secondArgExpr
        else {
            Issue.record("Expected second argument to be a lambda literal.")
            return
        }
    }

    // KSP-CAP-005: a top-level (or member) property/val initializer ending in a
    // trailing-lambda call -- e.g. the built-in `Comparator<T> { a, b -> ... }`
    // SAM constructor -- used to have its trailing lambda silently dropped by
    // `propertyHeadTokens`, because `parseTail` splits the lambda off into a
    // bare `.block` CST node that `propertyHeadTokens` stopped at. The
    // remaining `Comparator < Int >` tokens then re-parsed as a chained
    // comparison instead of a generic call, and the property's initializer
    // type came out as `Boolean` instead of `Comparator<Int>`. Function
    // declarations were never affected (they parse their body via the full
    // single-pass expression grammar), only top-level/member property
    // initializers routed through the CST head-token/re-parse split.
    @Test func testTopLevelPropertyWithGenericTrailingLambdaInitializerKeepsCallArguments() throws {
        let source = """
        fun <T> build(block: () -> T): T = block()
        val topLevelValue = build<Int> { 1 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let property = try #require(topLevelProperty(named: "topLevelValue", in: ast, interner: ctx.interner))
        let initializerID = try #require(property.initializer)
        guard let initializerExpr = ast.arena.expr(initializerID),
              case let .call(calleeID, typeArgs, args, _) = initializerExpr
        else {
            Issue.record("Expected property initializer to parse as a call expression.")
            return
        }

        #expect(typeArgs.count == 1)
        #expect(args.count == 1)
        guard let calleeExpr = ast.arena.expr(calleeID),
              case let .nameRef(calleeName, _) = calleeExpr
        else {
            Issue.record("Expected call callee to be a name reference.")
            return
        }
        #expect(ctx.interner.resolve(calleeName) == "build")
        guard let lambdaExpr = ast.arena.expr(args[0].expr),
              case .lambdaLiteral = lambdaExpr
        else {
            Issue.record("Expected trailing lambda argument.")
            return
        }
    }

    @Test func testTopLevelPropertyWithNonGenericTrailingLambdaInitializerKeepsCallArguments() throws {
        let source = """
        fun apply(block: () -> Int): Int = block()
        val topLevelValue = apply { 42 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let property = try #require(topLevelProperty(named: "topLevelValue", in: ast, interner: ctx.interner))
        let initializerID = try #require(property.initializer)
        guard let initializerExpr = ast.arena.expr(initializerID),
              case let .call(_, _, args, _) = initializerExpr
        else {
            Issue.record("Expected property initializer to parse as a call expression.")
            return
        }
        #expect(args.count == 1)
        guard let lambdaExpr = ast.arena.expr(args[0].expr),
              case .lambdaLiteral = lambdaExpr
        else {
            Issue.record("Expected trailing lambda argument.")
            return
        }
    }

    @Test func testClassMemberPropertyWithGenericTrailingLambdaInitializerKeepsCallArguments() throws {
        let source = """
        fun <T> build(block: () -> T): T = block()
        class Holder {
            val member = build<Int> { 7 }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        var memberProperty: PropertyDecl?
        outer: for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .classDecl(classDecl) = decl
                else { continue }
                for propertyDeclID in classDecl.memberProperties {
                    guard let propertyDecl = ast.arena.decl(propertyDeclID),
                          case let .propertyDecl(property) = propertyDecl,
                          ctx.interner.resolve(property.name) == "member"
                    else { continue }
                    memberProperty = property
                    break outer
                }
            }
        }
        let property = try #require(memberProperty)
        let initializerID = try #require(property.initializer)
        guard let initializerExpr = ast.arena.expr(initializerID),
              case let .call(_, typeArgs, args, _) = initializerExpr
        else {
            Issue.record("Expected member property initializer to parse as a call expression.")
            return
        }
        #expect(typeArgs.count == 1)
        #expect(args.count == 1)
        guard let lambdaExpr = ast.arena.expr(args[0].expr),
              case .lambdaLiteral = lambdaExpr
        else {
            Issue.record("Expected trailing lambda argument.")
            return
        }
    }
}
#endif

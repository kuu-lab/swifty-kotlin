#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// BUG-047: a top-level (or class member) property initializer ending in an
// expression with several top-level `{ }` blocks (`if/else`, `else if` chains)
// used to lose everything after the first block, because `parseTail` split off
// a single `.block` CST node and stopped -- only `try`/`catch`/`finally`
// continuations were handled. The `else` branch never reached the property's
// CST, so `val v = if (c) { "yes" } else { "no" }` silently evaluated to
// undefined behaviour on the false path.
extension CompilerCoreTests {
    @Test func testTopLevelPropertyIfElseInitializerKeepsElseBranch() throws {
        let source = """
        val topLevelIf = if (1 > 2) { "yes" } else { "no" }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let property = try #require(topLevelProperty(named: "topLevelIf", in: ast, interner: ctx.interner))
        let initializerID = try #require(property.initializer)
        guard let initializerExpr = ast.arena.expr(initializerID),
              case let .ifExpr(_, _, elseExpr, _) = initializerExpr
        else {
            Issue.record("Expected property initializer to parse as an if expression.")
            return
        }
        #expect(elseExpr != nil)
    }

    @Test func testTopLevelPropertyElseIfChainInitializerKeepsAllBranches() throws {
        let source = """
        val chained = if (1 > 2) { 1 } else if (2 > 3) { 2 } else { 3 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let property = try #require(topLevelProperty(named: "chained", in: ast, interner: ctx.interner))
        let initializerID = try #require(property.initializer)
        guard let initializerExpr = ast.arena.expr(initializerID),
              case let .ifExpr(_, _, outerElseID, _) = initializerExpr,
              let nestedID = outerElseID,
              let nestedExpr = ast.arena.expr(nestedID),
              case let .ifExpr(_, _, nestedElseID, _) = nestedExpr
        else {
            Issue.record("Expected property initializer to parse as a nested if/else-if expression.")
            return
        }
        #expect(nestedElseID != nil)
    }

    @Test func testClassMemberPropertyIfElseInitializerKeepsElseBranch() throws {
        let source = """
        class Holder {
            val member = if (1 > 2) { "yes" } else { "no" }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let property = try #require(
            memberProperty(named: "member", ofClass: "Holder", in: ast, interner: ctx.interner)
        )
        let initializerID = try #require(property.initializer)
        guard let initializerExpr = ast.arena.expr(initializerID),
              case let .ifExpr(_, _, elseExpr, _) = initializerExpr
        else {
            Issue.record("Expected member property initializer to parse as an if expression.")
            return
        }
        #expect(elseExpr != nil)
    }

    @Test func testTopLevelPropertyTryCatchInitializerStillParses() throws {
        let source = """
        val guarded = try { 1 } catch (e: Exception) { 2 } finally { }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let property = try #require(topLevelProperty(named: "guarded", in: ast, interner: ctx.interner))
        let initializerID = try #require(property.initializer)
        guard let initializerExpr = ast.arena.expr(initializerID),
              case let .tryExpr(_, catchClauses, finallyExpr, _) = initializerExpr
        else {
            Issue.record("Expected property initializer to parse as a try expression.")
            return
        }
        #expect(catchClauses.count == 1)
        #expect(finallyExpr != nil)
    }

    @Test func testTopLevelObjectLiteralPropertyInitializerKeepsByWhenAndObjectBody() throws {
        let source = """
        interface C { fun f(): String }
        object Impl : C { override fun f() = "OK" }
        val o = object : C by when (true) { else -> Impl } { fun own() = "own" }
        fun main() { println(o.f()) }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let parse0025 = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-PARSE-0025" }
        #expect(parse0025.isEmpty, "Expected the object literal and its delegate expression to stay in the property initializer.")

        let ast = try #require(ctx.ast)
        let property = try #require(topLevelProperty(named: "o", in: ast, interner: ctx.interner))
        #expect(property.delegateExpression == nil)
        let initializerID = try #require(property.initializer)
        guard case let .objectLiteral(_, objectDeclID?, _)? = ast.arena.expr(initializerID),
              case let .objectDecl(objectDecl)? = ast.arena.decl(objectDeclID)
        else {
            Issue.record("Expected the property initializer to contain a complete object literal.")
            return
        }

        let delegatedSupertype = try #require(objectDecl.superTypeEntries.first)
        let delegateExpressionID = try #require(delegatedSupertype.delegateExpression)
        guard case .whenExpr? = ast.arena.expr(delegateExpressionID) else {
            Issue.record("Expected the object literal's supertype delegate to remain a when expression.")
            return
        }
        #expect(objectDecl.memberFunctions.count == 1)
    }

    @Test(arguments: ["Impl", "make()", "when (true) { else -> Impl }"])
    func testObjectInterfaceDelegationStaysInsidePropertyInitializer(delegate: String) throws {
        let source = """
        interface C { fun f(): String }
        object Impl : C { override fun f() = "OK" }
        fun make(): C = Impl
        class Getter { operator fun getValue(thisRef: Any?, property: Any?): String = "property" }
        val actual by Getter()
        val item = object : C by \(delegate) { fun own() = "own" }
        class Wrapper { val member = object : C by Impl {} }
        val ordinary = object : C { override fun f() = "direct" }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let item = try #require(topLevelProperty(named: "item", in: ast, interner: ctx.interner))
        #expect(item.delegateExpression == nil)
        let initializer = try #require(item.initializer)
        guard case let .objectLiteral(_, declID?, _)? = ast.arena.expr(initializer),
              case let .objectDecl(objectDecl)? = ast.arena.decl(declID)
        else {
            Issue.record("Expected an object literal initializer.")
            return
        }
        let delegateID = try #require(objectDecl.superTypeEntries.first?.delegateExpression)
        switch (delegate, ast.arena.expr(delegateID)) {
        case ("Impl", .nameRef?), ("make()", .call?), ("when (true) { else -> Impl }", .whenExpr?):
            break
        default:
            Issue.record("Expected the original supertype delegate expression.")
        }
        #expect(objectDecl.memberFunctions.count == 1)

        let member = try #require(memberProperty(named: "member", ofClass: "Wrapper", in: ast, interner: ctx.interner))
        #expect(member.initializer != nil)
        #expect(member.delegateExpression == nil)
        let actual = try #require(topLevelProperty(named: "actual", in: ast, interner: ctx.interner))
        #expect(actual.initializer == nil)
        #expect(actual.delegateExpression != nil)
        let ordinary = try #require(topLevelProperty(named: "ordinary", in: ast, interner: ctx.interner))
        #expect(ordinary.initializer != nil)
        #expect(ordinary.delegateExpression == nil)
    }
}
#endif

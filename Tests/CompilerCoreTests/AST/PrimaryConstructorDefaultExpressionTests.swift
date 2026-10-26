#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrimaryConstructorDefaultExpressionTests {
    @Test(arguments: ["fun(): Int { return 7 }", "object {}", "object : Any() {}", "{ 7 }"])
    func multilineDefaultPreservesConstructorAndFollowingDeclarations(expression: String) throws {
        let source = """
        class Target constructor(val value: Any =
            \(expression))
        fun after() = 1
        fun main() { println(7) }
        """
        let parsed = parse(source)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        let declarations = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxNode? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id)
        }
        #expect(declarations.map(\.kind) == [.classDecl, .funDecl, .funDecl])
        #expect(declarations.first?.range.end.offset == "class Target constructor(val value: Any =\n    \(expression))".utf8.count)

        let (ast, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let target = try #require(firstClassDecl(named: "Target", in: ast, interner: ctx.interner))
        let parameter = try #require(target.primaryConstructorParams.first)
        #expect(target.primaryConstructorParams.count == 1)
        #expect(ctx.interner.resolve(parameter.name) == "value")
        #expect(parameter.hasDefaultValue)
        let value = try #require(parameter.defaultValue)
        switch ast.arena.expr(value) {
        case .lambdaLiteral:
            #expect(expression == "{ 7 }")
        case let .blockExpr(statements, trailingExpr, _):
            #expect(expression.hasPrefix("fun"))
            #expect(statements.count == 1)
            let callable = try #require(trailingExpr)
            guard case .callableRef = ast.arena.expr(callable) else {
                Issue.record("Expected an anonymous function callable reference")
                return
            }
        case .objectLiteral:
            #expect(expression.hasPrefix("object"))
        default:
            Issue.record("Expected a function or object default expression")
        }
        _ = try #require(firstFunDecl(named: "after", in: ast, interner: ctx.interner))
        _ = try #require(firstFunDecl(named: "main", in: ast, interner: ctx.interner))
    }

    @Test
    func multilineParameterPrefixesAfterAnonymousDefaultRemainInConstructor() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Target private constructor(
            val callback: () -> Int =
                fun(): Int { return 7 },
            @Suppress("unused")
            private
            val value: Any =
                object {},
            @Suppress("unused")
            public val tail: Int = 3,
        )
        fun after() = 1
        """, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let target = try #require(firstClassDecl(named: "Target", in: ast, interner: ctx.interner))
        #expect(target.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["callback", "value", "tail"])
        try #require(target.primaryConstructorParams.count == 3)
        #expect(target.primaryConstructorParams.allSatisfy { $0.defaultValue != nil })
        #expect(target.primaryConstructorParams[1].annotations.map(\.name) == ["Suppress"])
        #expect(target.primaryConstructorParams[1].propertyVisibilityModifiers == [.private])
        _ = try #require(firstFunDecl(named: "after", in: ast, interner: ctx.interner))
    }

    @Test(arguments: ["", " =", " = 7", " =\nfun(): Int { return 7 }", " =\nobject {}", " = { 7 }"])
    func missingClosingParenthesisRecoversRealDeclarations(defaultValue: String) {
        let parsed = parse("""
        class Target constructor(val value: Any\(defaultValue)
        fun after() = 1
        class Following
        object Named {}
        """)
        #expect(parsed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
        let kinds = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxKind? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id).kind
        }
        #expect(kinds == [.classDecl, .funDecl, .classDecl, .objectDecl])
    }

    @Test(arguments: ["fun after() = 1", "class Following", "object Named {}"])
    func missingDefaultExpressionDoesNotAbsorbNamedDeclaration(declaration: String) {
        let parsed = parse("class Target constructor(val value: Any =\n\(declaration)")
        #expect(parsed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
        let declarations = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxNode? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id)
        }
        #expect(declarations.count == 2)
        #expect(declarations.first?.kind == .classDecl)
        #expect(declarations.last?.kind == (declaration.hasPrefix("fun") ? .funDecl :
            declaration.hasPrefix("class") ? .classDecl : .objectDecl))
        #expect(declarations.last?.range.start.offset == "class Target constructor(val value: Any =\n".utf8.count)
    }

    @Test(arguments: ["fun(): Int { return 7 }", "object {}"])
    func secondaryConstructorRetainsAnonymousDefault(expression: String) {
        let parsed = parse("""
        class Target {
            constructor(value: Any =
                \(expression)) {}
            fun member() = 1
        }
        fun after() = 2
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(parsed.arena.nodes.count { $0.kind == .constructorDecl } == 1)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 2)
        #expect(parsed.arena.nodes.count { $0.kind == .objectDecl } == 0)
    }

    @Test(arguments: ["fun(): Int { return 7 }", "object {}"])
    func secondaryConstructorRecoversAfterDefaultWithMissingParenthesis(expression: String) {
        let parsed = parse("""
        class Target {
            constructor(value: Any =
                \(expression)
            fun member() = 1
        }
        fun after() = 2
        """)
        #expect(parsed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
        #expect(parsed.arena.nodes.count { $0.kind == .constructorDecl } == 1)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 2)
    }
}
#endif

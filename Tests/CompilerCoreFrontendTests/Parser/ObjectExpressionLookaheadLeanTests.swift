#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("object : Base {}", true),
        ("object {}", true),
        ("object Name : Base {}", false),
        ("object", false),
        ("`object` {}", false),
    ])
    func objectExpressionStartContracts(source: String, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        #expect(LeanParser.isObjectExpressionStart(parser) == accepts)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func anonymousObjectBodiesStayWithTheirFunctions() throws {
        let (ast, ctx) = try buildASTModule(from: """
        interface Marker
        fun withSupertype() =
            object : Marker {}
        fun withoutSupertype() =
            object {}
        object Named : Marker {}
        """, includeStdlib: false)
        for name in ["withSupertype", "withoutSupertype"] {
            let function = try #require(firstFunDecl(named: name, in: ast, interner: ctx.interner))
            guard case let .expr(body, _) = function.body, case .objectLiteral = ast.arena.expr(body) else {
                Issue.record("Expected an anonymous object expression in \(name)")
                continue
            }
        }
        let objectNames = ast.files.flatMap(\.topLevelDecls).compactMap { id -> String? in
            guard case let .objectDecl(object)? = ast.arena.decl(id) else { return nil }
            return ctx.interner.resolve(object.name)
        }
        #expect(objectNames == ["Named"])
        #expect(ctx.diagnostics.diagnostics.isEmpty)
    }
}
#endif

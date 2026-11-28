#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("field = 1", true),
        ("field\n: Int", true),
        ("`field` = 1", false),
        ("field == 1", false),
        ("field", false),
    ])
    func explicitBackingFieldStartContracts(source: String, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        #expect(LeanParser.isExplicitBackingFieldStart(parser) == accepts)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func explicitBackingFieldsStayWithTheirOwnProperties() throws {
        let (ast, ctx) = try buildASTModule(from: """
        val inferred: Int
            field = 1
        val typed: Int
            field: Int = 2
        val ordinary: Int = 3
        """, includeStdlib: false)

        for name in ["inferred", "typed"] {
            let property = try #require(topLevelProperty(named: name, in: ast, interner: ctx.interner))
            let field = try #require(property.explicitBackingField)
            #expect(field.initializer != nil)
        }
        let ordinary = try #require(topLevelProperty(named: "ordinary", in: ast, interner: ctx.interner))
        #expect(ordinary.explicitBackingField == nil)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
    }
}
#endif

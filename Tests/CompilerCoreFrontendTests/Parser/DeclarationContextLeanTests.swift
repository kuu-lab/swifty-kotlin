#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: ["context(x: Int) @Ann inline ", "@Ann context(x: Int) inline "])
    func declarationContextCanPrecedeOrFollowAnnotations(prefix: String) {
        let lexed = lex(prefix + "fun f() {}")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let node = parser.parseDeclaration()

        #expect(parser.arena.node(node).kind == .funDecl)
        #expect(parser.arena.tokens.filter { $0.kind == .softKeyword(.context) }.count == 1)
        #expect(parser.stream.index == lexed.tokens.count - 1)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: ["context ", "@Ann context "])
    func declarationContextMissingOpeningKeepsFollowingFunction(prefix: String) throws {
        let lexed = lex(prefix + "fun f() {}")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let function = try #require(lexed.tokens.first { $0.kind == .keyword(.fun) })
        let node = parser.parseDeclaration()
        let diagnostics = lexed.diagnostics.diagnostics

        #expect(parser.arena.node(node).kind == .funDecl)
        #expect(diagnostics.map(\.code) == ["KSWIFTK-PARSE-0001"])
        #expect(diagnostics.first?.primaryRange == parser.zeroWidthRange(at: function))
        #expect(parser.stream.peek().kind == .eof)
    }

    @Test
    func declarationContextDoesNotRetryAnotherClause() {
        let lexed = lex("@Ann context context")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.parseDeclaration()

        #expect(lexed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0001"])
        #expect(parser.stream.index == lexed.tokens.count - 1)
        #expect(!parser.arena.tokens.contains { $0.kind == .eof })
    }
}
#endif

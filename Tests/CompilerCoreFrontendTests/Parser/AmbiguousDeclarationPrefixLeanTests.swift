#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("@", true),
        ("context", true),
        ("context.member()", true),
        ("private", true),
        ("suspend", true),
        ("value", true),
        ("`context`", false),
        ("`private`", false),
        ("fun", false),
        ("object", false),
        ("constructor", false),
        ("field", false),
        ("", false),
    ])
    func ambiguousDeclarationPrefixContracts(source: String, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        #expect(parser.isAmbiguousDeclarationPrefix(parser.stream.peek()) == accepts)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.genuineDeclarationLookahead.isEmpty)
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }
}
#endif

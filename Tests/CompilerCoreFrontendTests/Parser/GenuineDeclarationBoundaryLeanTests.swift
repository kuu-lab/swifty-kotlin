#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: ["fun named()", "class Named", "object {}", "val x = 1", "identifier", ""])
    func genuineBoundarySkipsTheCacheAndScanForOtherTokens(source: String) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        parser.genuineDeclarationLookahead[1] = false
        #expect(LeanParser.isGenuineDeclarationBoundary(parser))
        #expect(parser.genuineDeclarationLookahead == [1: false])
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: [
        ("fun () {}", false),
        ("context = value", false),
        ("context(x: T) fun named()", true),
        ("private fun named()", true),
        ("value fun named()", false),
        ("@A fun named()", true),
        ("@A expression", false),
    ])
    func genuineBoundaryScansCandidates(source: String, expected: Bool) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        #expect(LeanParser.isGenuineDeclarationBoundary(parser) == expected)
        #expect(parser.genuineDeclarationLookahead[0] == expected)
        #expect(parser.stream.index == 0)
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func overBudgetGenuineDeclarationIsABoundaryAndCachesItsPrefixes() {
        let limit = KotlinParser.declarationLookaheadWorkLimit
        let lexed = lex(String(repeating: "private ", count: limit) + "fun next()")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        #expect(LeanParser.isGenuineDeclarationBoundary(parser))
        #expect(parser.genuineDeclarationLookahead.count == limit)
        #expect(parser.genuineDeclarationLookahead[0] == true)
        #expect(parser.genuineDeclarationLookahead[limit] == nil)
        #expect(LeanParser.isGenuineDeclarationBoundary(parser))
        #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0007"])
        #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[limit].range)
        #expect(parser.stream.index == 0)
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("fun next()", .declaration, 0, .keyword(.fun)),
        ("private @A inline @field:pkg.Tag<T>(1) suspend fun next()", .declaration, 17, .keyword(.fun)),
        ("private @A context(x: T) fun next()", .declaration, 3, .softKeyword(.context)),
        ("private @A", .declaration, 3, .eof),
        ("@A @B private C", .annotations, 4, .keyword(.private)),
        ("@receiver:A @`receiver`:B @field:C", .receiver, 8, .symbol(.at)),
    ] as [(String, LeanParser.LeadingPrefixMode, Int, TokenKind)])
    func leadingPrefixStopsAtFirstOtherToken(
        source: String, mode: LeanParser.LeadingPrefixMode, count: Int, next: TokenKind
    ) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        parser.consumeLeadingPrefix(mode, into: &children, range: &range)
        #expect(parser.stream.index == 1 + count)
        #expect(parser.stream.peek().kind == next)
        #expect(parser.arena.tokens == Array(lexed.tokens.dropFirst().prefix(count)))
        #expect(children.count == count)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func leadingPrefixRecoversBeforeDeclarationAndHandlesLargePrefixes() {
        let lexed = lex("private @A(1\nfun next()")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        parser.consumeLeadingPrefix(.declaration, into: &children, range: &range)
        #expect(parser.stream.index == 5)
        #expect(parser.stream.peek().kind == .keyword(.fun))
        #expect(parser.arena.tokens.last?.kind == .missing(expected: .symbol(.rParen)))
        #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0001"])

        let repeats = KotlinParser.declarationLookaheadWorkLimit + 1
        let long = lex(String(repeating: "@A private ", count: repeats))
        let longParser = KotlinParser(tokens: long.tokens, interner: long.interner, diagnostics: long.diagnostics)
        var longChildren: [SyntaxChild] = []
        var longRange = RangeAccumulator()
        longParser.consumeLeadingPrefix(.declaration, into: &longChildren, range: &longRange)
        #expect(longParser.stream.index == 3 * repeats)
        #expect(longParser.stream.atEOF())
        #expect(longChildren.count == 3 * repeats)
        #expect(longParser.diagnostics.diagnostics.isEmpty)
    }
}
#endif

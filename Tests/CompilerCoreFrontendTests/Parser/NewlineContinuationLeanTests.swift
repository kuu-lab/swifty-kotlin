#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        (TokenKind.symbol(.dot), true),
        (.symbol(.questionDot), true),
        (.symbol(.questionColon), true),
        (.symbol(.ampAmp), true),
        (.symbol(.barBar), true),
        (.keyword(.else), true),
        (.keyword(.catch), true),
        (.keyword(.finally), true),
        (.keyword(.as), true),
        (.symbol(.plus), false),
        (.symbol(.minus), false),
        (.symbol(.doubleColon), false),
        (.symbol(.comma), false),
        (.symbol(.questionQuestion), false),
        (.symbol(.lParen), false),
        (.symbol(.assign), false),
        (.softKeyword(.by), false),
        (.keyword(.in), false),
        (.eof, false),
    ])
    func leadingNewlineContinuationContracts(kind: TokenKind, continues: Bool) {
        let lexed = lex("anchor")
        let token = Token(kind: kind, range: lexed.tokens[0].range, leadingTrivia: [.newline])

        #expect(LeanParser.continuesExpressionBeforeNewline(token, diagnostics: lexed.diagnostics) == continues)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: [
        (".other", true),
        ("?.other", true),
        ("?: 2", true),
        ("&& other", true),
        ("|| other", true),
        ("as Any", true),
        ("+ 2", false),
        ("- 2", false),
    ])
    func leadingNewlineContinuationInPropertyTail(suffix: String, continues: Bool) throws {
        let firstLine = "val sample = 1"
        let source = firstLine + "\n" + suffix
        let parsed = parse(source)
        let property = try #require(parsed.arena.nodes.first { $0.kind == .propertyDecl })

        #expect(property.range.end.offset == (continues ? source.utf8.count : firstLine.utf8.count))
        #expect(parsed.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: [
        (TokenKind.softKeyword(.by), true),
        (.keyword(.as), true),
        (.keyword(.else), true),
        (.symbol(.plus), true),
        (.symbol(.minus), true),
        (.symbol(.notTripleEqual), true),
        (.symbol(.slashAssign), true),
        (.symbol(.dotDotLt), true),
        (.symbol(.questionColon), true),
        (.symbol(.doubleColon), true),
        (.keyword(.catch), false),
        (.keyword(.finally), false),
        (.keyword(.in), false),
        (.softKeyword(.where), false),
        (.symbol(.lessThan), false),
        (.symbol(.plusPlus), false),
        (.symbol(.lParen), false),
        (.symbol(.bangBang), false),
        (.eof, false),
    ])
    func newlineContinuationContracts(kind: TokenKind, continues: Bool) {
        let lexed = lex("anchor")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()

        #expect(LeanParser.continuesExpressionAfterNewline(parser, kind: kind) == continues)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }
}
#endif

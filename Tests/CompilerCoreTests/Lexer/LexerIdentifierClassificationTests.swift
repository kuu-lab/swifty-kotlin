@testable import CompilerCore
import Testing

@Suite
struct LexerIdentifierClassificationTests {
    @Test
    func repeatedNamesKeepTheirClassificationTriviaAndRanges() {
        let (tokens, interner, diagnostics) = lex("when by item\n\twhen by item")
        let expectedKinds: [TokenKind] = [.keyword(.when), .softKeyword(.by), .identifier(interner.intern("item"))]
        #expect(tokens.map(\.kind) == expectedKinds + expectedKinds + [.eof])
        #expect(tokens.map { $0.range.start.offset } == [0, 5, 8, 14, 19, 22, 26])
        #expect(tokens.map { $0.range.end.offset } == [4, 7, 12, 18, 21, 26, 26])
        #expect(tokens.map(\.leadingTrivia) == [[], [.spaces(1)], [.spaces(1)], [.newline, .tabs(1)], [.spaces(1)], [.spaces(1)], []])
        #expect(!diagnostics.hasError)
    }

    @Test
    func keywordSpellingRemainsAnIdentifierInBackticksAndSimpleTemplates() {
        let (tokens, interner, diagnostics) = lex("when by `when` `by` \"$when$by\" when by")
        let whenID = interner.intern("when")
        let byID = interner.intern("by")
        #expect(tokens.map(\.kind) == [
            .keyword(.when), .softKeyword(.by),
            .backtickedIdentifier(whenID), .backtickedIdentifier(byID),
            .stringQuote, .templateSimpleNameStart, .identifier(whenID),
            .templateSimpleNameStart, .identifier(byID), .stringQuote,
            .keyword(.when), .softKeyword(.by), .eof,
        ])
        #expect(!diagnostics.hasError)
    }

    @Test
    func dollarIsRejectedOutsideStringTemplates() {
        let result = lex("""
        val a$b = 1
        val $x = 2
        val `$x` = 3
        val text = "$a$b"
        """)
        let aID = result.interner.intern("a")
        let bID = result.interner.intern("b")
        let xID = result.interner.intern("x")
        let escapedDollarID = result.interner.intern("$x")
        let textID = result.interner.intern("text")

        #expect(result.tokens.map(\.kind) == [
            .keyword(.val), .identifier(aID), .identifier(bID), .symbol(.assign), .intLiteral("1"),
            .keyword(.val), .identifier(xID), .symbol(.assign), .intLiteral("2"),
            .keyword(.val), .backtickedIdentifier(escapedDollarID), .symbol(.assign), .intLiteral("3"),
            .keyword(.val), .identifier(textID), .symbol(.assign),
            .stringQuote, .templateSimpleNameStart, .identifier(aID),
            .templateSimpleNameStart, .identifier(bID), .stringQuote, .eof,
        ])
        #expect(result.diagnostics.diagnostics.map(\.code) == [
            "KSWIFTK-LEX-0001", "KSWIFTK-LEX-0001",
        ])
    }

    @Test
    func repeatedIdentifiersUseTheirOwnInterner() {
        let firstInterner = StringInterner()
        let secondInterner = StringInterner()
        secondInterner.preload(["seed", "another"])
        var identifiers: [InternedString] = []
        for interner in [firstInterner, secondInterner] {
            let tokens = lex("item item", interner: interner).tokens
            let expected = interner.intern("item")
            #expect(tokens.map(\.kind) == [.identifier(expected), .identifier(expected), .eof])
            #expect(interner.resolve(expected) == "item")
            identifiers.append(expected)
        }
        #expect(identifiers[0] != identifiers[1])
    }
}

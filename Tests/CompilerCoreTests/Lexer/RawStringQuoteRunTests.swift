#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct RawStringQuoteRunTests {
    @Test(arguments: [3, 4, 5, 6, 7, 8], ["", "$$", "$$$"])
    func closingRunPreservesContentAndRanges(quoteCount: Int, prefix: String) {
        let opening = prefix + String(repeating: "\"", count: 3)
        let content = "é \" and \"\" "
        let source = opening + content + String(repeating: "\"", count: quoteCount) + ";next"
        let result = lex(source)
        let quote: TokenKind = prefix.isEmpty ? .rawStringQuote : .multiDollarRawStringQuote(dollarCount: prefix.count)
        let closingStart = opening.utf8.count + content.utf8.count + quoteCount - 3

        #expect(result.diagnostics.diagnostics.isEmpty)
        #expect(result.tokens.map(\.kind) == [
            quote,
            .stringSegment(result.interner.intern(content + String(repeating: "\"", count: quoteCount - 3))),
            quote, .symbol(.semicolon), .identifier(result.interner.intern("next")), .eof,
        ])
        #expect(result.tokens[0].range.start.offset == 0)
        #expect(result.tokens[0].range.end.offset == opening.utf8.count)
        #expect(result.tokens[1].range.start.offset == opening.utf8.count)
        #expect(result.tokens[1].range.end.offset == closingStart)
        #expect(result.tokens[2].range.start.offset == closingStart)
        #expect(result.tokens[2].range.end.offset == closingStart + 3)
        #expect(result.tokens[3].range.start.offset == closingStart + 3)
    }

    @Test(arguments: [6, 7, 8], ["", "$$"])
    func allQuoteLiteral(quoteCount: Int, prefix: String) {
        let result = lex(prefix + String(repeating: "\"", count: quoteCount))
        let segments = result.tokens.compactMap { token -> String? in
            guard case let .stringSegment(value) = token.kind else { return nil }
            return result.interner.resolve(value)
        }
        #expect(result.diagnostics.diagnostics.isEmpty)
        #expect(segments == (quoteCount == 6 ? [] : [String(repeating: "\"", count: quoteCount - 6)]))
        #expect(result.tokens[result.tokens.count - 2].range.start.offset == prefix.count + quoteCount - 3)
        #expect(result.tokens.last?.range.start.offset == prefix.count + quoteCount)
    }

    @Test(arguments: ["", "$$", "$$$"])
    func templateBoundariesPreserveTrailingQuotes(prefix: String) {
        let dollars = prefix.isEmpty ? "$" : prefix
        let source = prefix + "\"\"\"a " + dollars + "name \"\" " + dollars + "{1}終\"\"\"\"\";"
        let result = lex(source)
        let quote: TokenKind = prefix.isEmpty ? .rawStringQuote : .multiDollarRawStringQuote(dollarCount: prefix.count)
        #expect(result.diagnostics.diagnostics.isEmpty)
        #expect(result.tokens.map(\.kind) == [
            quote, .stringSegment(result.interner.intern("a ")),
            .templateSimpleNameStart, .identifier(result.interner.intern("name")),
            .stringSegment(result.interner.intern(" \"\" ")),
            .templateExprStart, .intLiteral("1"), .templateExprEnd,
            .stringSegment(result.interner.intern("終\"\"")), quote, .symbol(.semicolon), .eof,
        ])
        let tail = result.tokens[result.tokens.count - 4]
        #expect(tail.range.end.offset == source.utf8.count - 4)
        #expect(tail.range.start.offset == source.utf8.count - 9)
    }

    @Test
    func threeQuotesRemainUnterminatedOpening() {
        let result = lex("\"\"\"")
        #expect(result.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-LEX-0002"])
        #expect(result.tokens.map(\.kind) == [.rawStringQuote, .eof])
    }
}
#endif

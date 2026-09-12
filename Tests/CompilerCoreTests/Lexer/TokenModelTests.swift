#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TokenModelTests {
    @Test
    func testTriviaPieceBlockCommentAndShebang() {
        let block = TriviaPiece.blockComment("/* comment */")
        let shebang = TriviaPiece.shebang("#!/usr/bin/env kotlin")
        #expect(block != shebang)
        #expect(block == .blockComment("/* comment */"))
        #expect(shebang == .shebang("#!/usr/bin/env kotlin"))
    }

    @Test
    func testTokenKindMissingBacktickedIdentifierAndCharLiteral() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 1)

        let missing = Token(kind: .missing(expected: .keyword(.fun)), range: range)
        #expect(missing.kind == .missing(expected: .keyword(.fun)))

        let backticked = Token(kind: .backtickedIdentifier(interner.intern("myFun")), range: range)
        guard case let .backtickedIdentifier(name) = backticked.kind else {
            Issue.record("Expected backtickedIdentifier"); return
        }
        #expect(interner.resolve(name) == "myFun")

        let charLit = Token(kind: .charLiteral(65), range: range)
        guard case let .charLiteral(code) = charLit.kind else {
            Issue.record("Expected charLiteral"); return
        }
        #expect(code == 65)
    }

    @Test
    func testTokenInitializerHandlesDefaultsAndExplicitTrivia() {
        let range = makeRange(start: 0, end: 4)
        let defaultToken = Token(kind: .keyword(.fun), range: range)
        #expect(defaultToken.leadingTrivia == [])
        #expect(defaultToken.trailingTrivia == [])

        let token = Token(
            kind: .symbol(.plus),
            range: range,
            leadingTrivia: [.spaces(1), .tabs(1)],
            trailingTrivia: [.newline, .lineComment("// trailing")]
        )
        #expect(token.kind == .symbol(.plus))
        #expect(token.range == range)
        #expect(token.leadingTrivia == [.spaces(1), .tabs(1)])
        #expect(token.trailingTrivia == [.newline, .lineComment("// trailing")])
    }

    @Test
    func testKeywordInitFromInvalidRawValueReturnsNil() {
        #expect(Keyword(rawValue: "notAKeyword") == nil)
        #expect(Keyword(rawValue: "") == nil)
        #expect(Keyword(rawValue: "FUN") == nil)
    }

    @Test
    func testSoftKeywordInitFromInvalidRawValueReturnsNil() {
        #expect(SoftKeyword(rawValue: "notASoftKeyword") == nil)
        #expect(SoftKeyword(rawValue: "") == nil)
        #expect(SoftKeyword(rawValue: "GET") == nil)
    }

}
#endif

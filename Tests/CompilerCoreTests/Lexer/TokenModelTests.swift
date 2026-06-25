@testable import CompilerCore
import XCTest

final class TokenModelTests: XCTestCase {
    func testTriviaPieceBlockCommentAndShebang() {
        let block = TriviaPiece.blockComment("/* comment */")
        let shebang = TriviaPiece.shebang("#!/usr/bin/env kotlin")
        XCTAssertNotEqual(block, shebang)
        XCTAssertEqual(block, .blockComment("/* comment */"))
        XCTAssertEqual(shebang, .shebang("#!/usr/bin/env kotlin"))
    }

    func testTokenKindMissingBacktickedIdentifierAndCharLiteral() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 1)

        let missing = Token(kind: .missing(expected: .keyword(.fun)), range: range)
        XCTAssertEqual(missing.kind, .missing(expected: .keyword(.fun)))

        let backticked = Token(kind: .backtickedIdentifier(interner.intern("myFun")), range: range)
        guard case let .backtickedIdentifier(name) = backticked.kind else {
            return XCTFail("Expected backtickedIdentifier")
        }
        XCTAssertEqual(interner.resolve(name), "myFun")

        let charLit = Token(kind: .charLiteral(65), range: range)
        guard case let .charLiteral(code) = charLit.kind else {
            return XCTFail("Expected charLiteral")
        }
        XCTAssertEqual(code, 65)
    }

    func testTokenInitializerHandlesDefaultsAndExplicitTrivia() {
        let range = makeRange(start: 0, end: 4)
        let defaultToken = Token(kind: .keyword(.fun), range: range)
        XCTAssertEqual(defaultToken.leadingTrivia, [])
        XCTAssertEqual(defaultToken.trailingTrivia, [])

        let token = Token(
            kind: .symbol(.plus),
            range: range,
            leadingTrivia: [.spaces(1), .tabs(1)],
            trailingTrivia: [.newline, .lineComment("// trailing")]
        )
        XCTAssertEqual(token.kind, .symbol(.plus))
        XCTAssertEqual(token.range, range)
        XCTAssertEqual(token.leadingTrivia, [.spaces(1), .tabs(1)])
        XCTAssertEqual(token.trailingTrivia, [.newline, .lineComment("// trailing")])
    }

    func testKeywordInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(Keyword(rawValue: "notAKeyword"))
        XCTAssertNil(Keyword(rawValue: ""))
        XCTAssertNil(Keyword(rawValue: "FUN"))
    }

    func testSoftKeywordInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(SoftKeyword(rawValue: "notASoftKeyword"))
        XCTAssertNil(SoftKeyword(rawValue: ""))
        XCTAssertNil(SoftKeyword(rawValue: "GET"))
    }
}

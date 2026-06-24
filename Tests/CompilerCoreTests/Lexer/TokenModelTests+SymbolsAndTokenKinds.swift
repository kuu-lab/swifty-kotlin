@testable import CompilerCore
import XCTest

extension TokenModelTests {
    func testSymbolInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(Symbol(rawValue: "notASymbol"))
        XCTAssertNil(Symbol(rawValue: ""))
        XCTAssertNil(Symbol(rawValue: "+++"))
    }

    func testTokenKindAllVariantsAreMutuallyDistinct() {
        let interner = StringInterner()
        let id = interner.intern("x")

        let allKinds: [TokenKind] = [
            .identifier(id),
            .backtickedIdentifier(id),
            .keyword(.fun),
            .softKeyword(.get),
            .intLiteral("1"),
            .longLiteral("1L"),
            .floatLiteral("1.0f"),
            .doubleLiteral("1.0"),
            .charLiteral(65),
            .stringSegment(id),
            .stringQuote,
            .rawStringQuote,
            .templateExprStart,
            .templateExprEnd,
            .templateSimpleNameStart,
            .symbol(.plus),
            .eof,
            .missing(expected: .eof),
        ]

        for i in 0 ..< allKinds.count {
            for j in 0 ..< allKinds.count {
                if i == j {
                    XCTAssertEqual(allKinds[i], allKinds[j])
                } else {
                    XCTAssertNotEqual(allKinds[i], allKinds[j])
                }
            }
        }
    }
}

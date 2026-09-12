#if canImport(Testing)
@testable import CompilerCore
import Testing

extension TokenModelTests {
    @Test
    func testSymbolInitFromInvalidRawValueReturnsNil() {
        #expect(Symbol(rawValue: "notASymbol") == nil)
        #expect(Symbol(rawValue: "") == nil)
        #expect(Symbol(rawValue: "+++") == nil)
    }

    @Test
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
                    #expect(allKinds[i] == allKinds[j], "TokenKind at index \(i) should equal itself")
                } else {
                    #expect(allKinds[i] != allKinds[j], "TokenKind at index \(i) should not equal index \(j)")
                }
            }
        }
    }
}
#endif

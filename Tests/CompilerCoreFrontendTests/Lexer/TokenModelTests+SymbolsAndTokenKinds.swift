#if canImport(Testing)
@testable import CompilerCore
import Testing

extension TokenModelTests {
    // MARK: - Symbol

    /// Spelling table for every `Symbol`. Unlike `Keyword`/`SoftKeyword`, these
    /// raw values are written out explicitly in `TokenModel.swift`, and the
    /// lexer derives byte ranges from them, so the spellings are real contract.
    /// The `allCases` guard keeps the table from drifting behind the enum.
    private static let symbolSpellings: [(Symbol, String)] = [
        (.plus, "+"),
        (.minus, "-"),
        (.star, "*"),
        (.slash, "/"),
        (.percent, "%"),
        (.plusPlus, "++"),
        (.minusMinus, "--"),
        (.amp, "&"),
        (.ampAmp, "&&"),
        (.barBar, "||"),
        (.bang, "!"),
        (.equalEqual, "=="),
        (.bangEqual, "!="),
        (.tripleEqual, "==="),
        (.notTripleEqual, "!=="),
        (.lessThan, "<"),
        (.lessOrEqual, "<="),
        (.greaterThan, ">"),
        (.greaterOrEqual, ">="),
        (.assign, "="),
        (.plusAssign, "+="),
        (.minusAssign, "-="),
        (.starAssign, "*="),
        (.slashAssign, "/="),
        (.percentAssign, "%="),
        (.dotDot, ".."),
        (.dotDotLt, "..<"),
        (.questionQuestion, "??"),
        (.question, "?"),
        (.questionDot, "?."),
        (.questionColon, "?:"),
        (.bangBang, "!!"),
        (.doubleColon, "::"),
        (.comma, ","),
        (.dot, "."),
        (.semicolon, ";"),
        (.colon, ":"),
        (.arrow, "->"),
        (.fatArrow, "=>"),
        (.lParen, "("),
        (.rParen, ")"),
        (.lBracket, "["),
        (.rBracket, "]"),
        (.lBrace, "{"),
        (.rBrace, "}"),
        (.at, "@"),
        (.hash, "#"),
    ]

    @Test
    func testSymbolSpellingsCoverEveryCaseAndRoundTrip() {
        #expect(
            Set(Self.symbolSpellings.map(\.0)) == Set(Symbol.allCases),
            "symbolSpellings is out of sync with Symbol.allCases"
        )
        for (symbol, spelling) in Self.symbolSpellings {
            #expect(symbol.rawValue == spelling, "Symbol.\(symbol) rawValue mismatch")
            #expect(Symbol(rawValue: spelling) == symbol, "Symbol(rawValue: \"\(spelling)\") round-trip failed")
        }
    }

    @Test
    func testSymbolInitFromInvalidRawValueReturnsNil() {
        #expect(Symbol(rawValue: "notASymbol") == nil)
        #expect(Symbol(rawValue: "") == nil)
        #expect(Symbol(rawValue: "+++") == nil)
    }

    @Test
    func testDistinctSymbolsProduceDistinctTokenKinds() {
        #expect(TokenKind.symbol(.plus) != TokenKind.symbol(.minus))
        #expect(TokenKind.symbol(.lParen) != TokenKind.symbol(.rParen))
    }

    // MARK: - TokenKind

    /// `TokenKind` carries associated values (and an `indirect` case), so it
    /// cannot be `CaseIterable`; this list is maintained by hand. Keep one
    /// entry per case so the matrix below covers the whole enum.
    private static func allTokenKinds(interner: StringInterner) -> [TokenKind] {
        let id = interner.intern("x")
        return [
            .identifier(id),
            .backtickedIdentifier(id),
            .keyword(.fun),
            .softKeyword(.get),
            .intLiteral("1"),
            .longLiteral("1L"),
            .uintLiteral("1u"),
            .ulongLiteral("1uL"),
            .floatLiteral("1.0f"),
            .doubleLiteral("1.0"),
            .charLiteral(65),
            .stringSegment(id),
            .stringQuote,
            .rawStringQuote,
            .multiDollarStringQuote(dollarCount: 2),
            .multiDollarRawStringQuote(dollarCount: 2),
            .templateExprStart,
            .templateExprEnd,
            .templateSimpleNameStart,
            .symbol(.plus),
            .eof,
            .missing(expected: .eof),
        ]
    }

    @Test
    func testTokenKindAllVariantsAreMutuallyDistinct() {
        let allKinds = Self.allTokenKinds(interner: StringInterner())

        for i in allKinds.indices {
            for j in allKinds.indices where i != j {
                #expect(allKinds[i] != allKinds[j], "TokenKind at index \(i) should not equal index \(j)")
            }
        }
    }

    /// Cases whose payload participates in equality: two values of the *same*
    /// case must still differ when their payloads differ. The mutual-distinctness
    /// matrix above only carries one payload per case, so it cannot see this.
    @Test
    func testTokenKindPayloadsParticipateInEquality() {
        let interner = StringInterner()
        let id = interner.intern("myVar")
        let other = interner.intern("otherVar")

        #expect(TokenKind.identifier(id) != .identifier(other))
        #expect(TokenKind.backtickedIdentifier(id) != .backtickedIdentifier(other))
        #expect(TokenKind.stringSegment(id) != .stringSegment(other))
        #expect(TokenKind.intLiteral("42") != .intLiteral("0"))
        #expect(TokenKind.longLiteral("42L") != .longLiteral("0L"))
        #expect(TokenKind.uintLiteral("42u") != .uintLiteral("0u"))
        #expect(TokenKind.ulongLiteral("42uL") != .ulongLiteral("0uL"))
        #expect(TokenKind.floatLiteral("3.14f") != .floatLiteral("2.71f"))
        #expect(TokenKind.doubleLiteral("3.14") != .doubleLiteral("2.71"))
        #expect(TokenKind.charLiteral(0x41) != .charLiteral(0x42))
        #expect(TokenKind.multiDollarStringQuote(dollarCount: 2) != .multiDollarStringQuote(dollarCount: 3))
        #expect(TokenKind.multiDollarRawStringQuote(dollarCount: 2) != .multiDollarRawStringQuote(dollarCount: 3))
        #expect(TokenKind.keyword(.val) != .keyword(.var))
        #expect(TokenKind.softKeyword(.get) != .softKeyword(.set))
        #expect(TokenKind.symbol(.lParen) != .symbol(.rParen))

        // `missing` is `indirect`: its payload is itself a TokenKind, and a
        // missing token is never equal to the token it stands in for.
        #expect(TokenKind.missing(expected: .keyword(.val)) == .missing(expected: .keyword(.val)))
        #expect(TokenKind.missing(expected: .keyword(.val)) != .missing(expected: .keyword(.var)))
        #expect(TokenKind.missing(expected: .keyword(.val)) != .keyword(.val))
        #expect(TokenKind.missing(expected: .symbol(.lParen)) != .missing(expected: .symbol(.rParen)))
    }
}
#endif

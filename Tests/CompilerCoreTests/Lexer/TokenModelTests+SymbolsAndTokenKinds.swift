#if canImport(Testing)
@testable import CompilerCore
import Testing

extension TokenModelTests {
    @Test
    func testSymbolAllCasesRawValues() {
        let expectedSymbols: [(Symbol, String)] = [
            (.plus, "+"),
            (.minus, "-"),
            (.star, "*"),
            (.slash, "/"),
            (.percent, "%"),
            (.plusPlus, "++"),
            (.minusMinus, "--"),
            (.ampAmp, "&&"),
            (.barBar, "||"),
            (.bang, "!"),
            (.equalEqual, "=="),
            (.bangEqual, "!="),
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

        for (symbol, expected) in expectedSymbols {
            #expect(symbol.rawValue == expected, "Symbol.\(symbol) rawValue mismatch")
        }
    }

    @Test
    func testSymbolInitFromRawValueRoundTrips() {
        let allRawValues = [
            "+", "-", "*", "/", "%", "++", "--", "&&", "||", "!",
            "==", "!=", "<", "<=", ">", ">=", "=", "+=", "-=", "*=",
            "/=", "%=", "..", "..<", "??", "?", "?.", "?:", "!!",
            "::", ",", ".", ";", ":", "->", "=>", "(", ")", "[", "]",
            "{", "}", "@", "#",
        ]

        for raw in allRawValues {
            let symbol = Symbol(rawValue: raw)
            #expect(symbol != nil, "Symbol(rawValue: \"\(raw)\") should not be nil")
            #expect(symbol?.rawValue == raw)
        }
    }

    @Test
    func testSymbolInitFromInvalidRawValueReturnsNil() {
        #expect(Symbol(rawValue: "notASymbol") == nil)
        #expect(Symbol(rawValue: "") == nil)
        #expect(Symbol(rawValue: "+++") == nil)
    }

    @Test
    func testSymbolTokenKindEquality() {
        let allSymbols: [Symbol] = [
            .plus, .minus, .star, .slash, .percent, .plusPlus, .minusMinus,
            .ampAmp, .barBar, .bang, .equalEqual, .bangEqual, .lessThan,
            .lessOrEqual, .greaterThan, .greaterOrEqual, .assign, .plusAssign,
            .minusAssign, .starAssign, .slashAssign, .percentAssign, .dotDot,
            .dotDotLt, .questionQuestion, .question, .questionDot, .questionColon,
            .bangBang, .doubleColon, .comma, .dot, .semicolon, .colon, .arrow,
            .fatArrow, .lParen, .rParen, .lBracket, .rBracket, .lBrace, .rBrace,
            .at, .hash,
        ]

        for symbol in allSymbols {
            let kind = TokenKind.symbol(symbol)
            #expect(kind == TokenKind.symbol(symbol))
        }

        // Different symbols should not be equal
        #expect(TokenKind.symbol(.plus) != TokenKind.symbol(.minus))
        #expect(TokenKind.symbol(.lParen) != TokenKind.symbol(.rParen))
    }

    // MARK: - TokenKind: all variants

    @Test
    func testTokenKindLongLiteral() {
        let kind = TokenKind.longLiteral("42L")
        #expect(kind == TokenKind.longLiteral("42L"))
        #expect(kind != TokenKind.longLiteral("0L"))
        #expect(kind != TokenKind.intLiteral("42"))
    }

    @Test
    func testTokenKindFloatLiteral() {
        let kind = TokenKind.floatLiteral("3.14f")
        #expect(kind == TokenKind.floatLiteral("3.14f"))
        #expect(kind != TokenKind.floatLiteral("2.71f"))
        #expect(kind != TokenKind.doubleLiteral("3.14"))
    }

    @Test
    func testTokenKindDoubleLiteral() {
        let kind = TokenKind.doubleLiteral("3.14")
        #expect(kind == TokenKind.doubleLiteral("3.14"))
        #expect(kind != TokenKind.doubleLiteral("2.71"))
        #expect(kind != TokenKind.floatLiteral("3.14f"))
    }

    @Test
    func testTokenKindStringQuote() {
        let kind = TokenKind.stringQuote
        #expect(kind == TokenKind.stringQuote)
        #expect(kind != TokenKind.rawStringQuote)
    }

    @Test
    func testTokenKindRawStringQuote() {
        let kind = TokenKind.rawStringQuote
        #expect(kind == TokenKind.rawStringQuote)
        #expect(kind != TokenKind.stringQuote)
    }

    @Test
    func testTokenKindTemplateExprStart() {
        let kind = TokenKind.templateExprStart
        #expect(kind == TokenKind.templateExprStart)
        #expect(kind != TokenKind.templateExprEnd)
    }

    @Test
    func testTokenKindTemplateExprEnd() {
        let kind = TokenKind.templateExprEnd
        #expect(kind == TokenKind.templateExprEnd)
        #expect(kind != TokenKind.templateExprStart)
    }

    @Test
    func testTokenKindTemplateSimpleNameStart() {
        let kind = TokenKind.templateSimpleNameStart
        #expect(kind == TokenKind.templateSimpleNameStart)
        #expect(kind != TokenKind.templateExprStart)
        #expect(kind != TokenKind.templateExprEnd)
    }

    @Test
    func testTokenKindIntLiteral() {
        let kind = TokenKind.intLiteral("42")
        #expect(kind == TokenKind.intLiteral("42"))
        #expect(kind != TokenKind.intLiteral("0"))
        #expect(kind != TokenKind.longLiteral("42L"))
    }

    @Test
    func testTokenKindIdentifier() {
        let interner = StringInterner()
        let id = interner.intern("myVar")
        let kind = TokenKind.identifier(id)
        #expect(kind == TokenKind.identifier(id))

        let otherId = interner.intern("otherVar")
        #expect(kind != TokenKind.identifier(otherId))
        #expect(kind != TokenKind.backtickedIdentifier(id))
    }

    @Test
    func testTokenKindStringSegment() {
        let interner = StringInterner()
        let seg = interner.intern("hello world")
        let kind = TokenKind.stringSegment(seg)
        #expect(kind == TokenKind.stringSegment(seg))

        let otherSeg = interner.intern("other")
        #expect(kind != TokenKind.stringSegment(otherSeg))
    }

    @Test
    func testTokenKindEof() {
        let kind = TokenKind.eof
        #expect(kind == TokenKind.eof)
        #expect(kind != TokenKind.stringQuote)
    }

    @Test
    func testTokenKindMissingVariant() {
        let missing1 = TokenKind.missing(expected: .keyword(.val))
        let missing2 = TokenKind.missing(expected: .keyword(.val))
        let missing3 = TokenKind.missing(expected: .keyword(.var))

        #expect(missing1 == missing2)
        #expect(missing1 != missing3)
        #expect(missing1 != TokenKind.keyword(.val))

        // missing with symbol
        let missingSymbol = TokenKind.missing(expected: .symbol(.lParen))
        #expect(missingSymbol == TokenKind.missing(expected: .symbol(.lParen)))
        #expect(missingSymbol != TokenKind.missing(expected: .symbol(.rParen)))

        // missing with eof
        let missingEof = TokenKind.missing(expected: .eof)
        #expect(missingEof == TokenKind.missing(expected: .eof))
    }

    @Test
    func testTokenKindCharLiteral() {
        let kind = TokenKind.charLiteral(0x41)
        #expect(kind == TokenKind.charLiteral(0x41))
        #expect(kind != TokenKind.charLiteral(0x42))
        #expect(kind != TokenKind.intLiteral("65"))
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

        // Each kind should only be equal to itself
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

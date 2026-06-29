#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TokenStreamTests {
    @Test
    func testPeekReturnsSyntheticEOFForEmptyStreamAndNegativeOffset() {
        let stream = TokenStream([])

        #expect(stream.peek().kind == .eof)
        #expect(stream.peek(-1).kind == .eof)
    }

    @Test
    func testPeekReturnsInRangeTokenAndEOFForOutOfRange() {
        let interner = StringInterner()
        let first = makeToken(kind: .identifier(interner.intern("first")))
        let second = makeToken(kind: .identifier(interner.intern("second")), start: 1, end: 2)
        let stream = TokenStream([first, second])

        #expect(stream.peek(0) == first)
        #expect(stream.peek(1) == second)
        #expect(stream.peek(2).kind == .eof)
    }

    @Test
    func testAdvanceStopsAtEndWithoutOverflowingIndex() {
        let token = makeToken(kind: .keyword(.fun))
        let stream = TokenStream([token])

        #expect(stream.advance() == token)
        #expect(stream.index == 1)
        #expect(stream.advance().kind == .eof)
        #expect(stream.index == 1)
    }

    @Test
    func testAtEOFReflectsCurrentCursorState() {
        let nonEmpty = TokenStream([makeToken(kind: .keyword(.if))])
        #expect(!(nonEmpty.atEOF()))
        _ = nonEmpty.advance()
        #expect(nonEmpty.atEOF())

        let empty = TokenStream([])
        #expect(empty.atEOF())
    }

    @Test
    func testConsumeIfConsumesOnlyWhenPredicateMatches() {
        let interner = StringInterner()
        let first = makeToken(kind: .identifier(interner.intern("x")))
        let second = makeToken(kind: .symbol(.plus), start: 1, end: 2)
        let stream = TokenStream([first, second])

        let consumed = stream.consumeIf { token in
            if case .identifier = token.kind { return true }
            return false
        }
        #expect(consumed == first)
        #expect(stream.index == 1)

        let notConsumed = stream.consumeIf { token in
            if case .keyword = token.kind { return true }
            return false
        }
        #expect(notConsumed == nil)
        #expect(stream.index == 1)
    }

    // MARK: - Additional Coverage

    @Test
    func testPeekConsecutivePositiveOffsetsOutOfRange() {
        let interner = StringInterner()
        let token = makeToken(kind: .identifier(interner.intern("only")))
        let stream = TokenStream([token])

        // offset 0 is valid
        #expect(stream.peek(0) == token)
        // offsets 1..5 are all out of range → synthetic EOF
        for offset in 1 ... 5 {
            #expect(stream.peek(offset).kind == .eof, "peek(\(offset)) should return EOF for a single-element stream")
        }
    }

    @Test
    func testConsecutiveAdvanceOnEmptyStream() {
        let stream = TokenStream([])

        // Calling advance() repeatedly on an empty stream should always
        // return synthetic EOF and never move the index past 0.
        for _ in 0 ..< 5 {
            let token = stream.advance()
            #expect(token.kind == .eof)
            #expect(stream.index == 0)
        }
    }

    @Test
    func testConsumeIfPredicateCanAccessTokenDetails() {
        let interner = StringInterner()
        let id = makeToken(kind: .identifier(interner.intern("hello")))
        let plus = makeToken(kind: .symbol(.plus), start: 5, end: 6)
        let num = makeToken(kind: .intLiteral("42"), start: 6, end: 8)
        let stream = TokenStream([id, plus, num])

        // Complex predicate: identifier AND the interned name resolves to "hello"
        let matched = stream.consumeIf { token in
            if case let .identifier(interned) = token.kind {
                return interner.resolve(interned) == "hello"
            }
            return false
        }
        #expect(matched == id)
        #expect(stream.index == 1)

        // Complex predicate: symbol that is either plus or minus
        let matchedSymbol = stream.consumeIf { token in
            if case let .symbol(sym) = token.kind {
                return sym == .plus || sym == .minus
            }
            return false
        }
        #expect(matchedSymbol == plus)
        #expect(stream.index == 2)

        // Complex predicate that does NOT match: intLiteral with value > 100
        let noMatch = stream.consumeIf { token in
            if case let .intLiteral(value) = token.kind,
               let intValue = Int(value)
            {
                return intValue > 100
            }
            return false
        }
        #expect(noMatch == nil)
        #expect(stream.index == 2)
    }
}
#endif

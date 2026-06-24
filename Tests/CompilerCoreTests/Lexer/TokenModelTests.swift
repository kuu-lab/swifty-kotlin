#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TokenModelTests {
    @Test
    func testStringInternerReusesIDsAndResolvesInternedValues() {
        let interner = StringInterner()

        let fooA = interner.intern("foo")
        let fooB = interner.intern("foo")
        let bar = interner.intern("bar")

        #expect(fooA == fooB)
        #expect(fooA != bar)
        #expect(interner.resolve(fooA) == "foo")
        #expect(interner.resolve(bar) == "bar")
    }

    @Test
    func testStringInternerResolveReturnsEmptyForOutOfRangeIDs() {
        let interner = StringInterner()
        _ = interner.intern("only")

        #expect(interner.resolve(InternedString(rawValue: -1)) == "")
        #expect(interner.resolve(InternedString(rawValue: 100)) == "")
    }

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
    func testInternedStringInvalidAndEquality() {
        #expect(InternedString.invalid.rawValue == -1)
        #expect(InternedString() == InternedString.invalid)
        #expect(InternedString(rawValue: 0) != InternedString(rawValue: 1))
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

    // MARK: - Keyword enum: all cases

    @Test
    func testKeywordAllCasesRawValues() {
        let expectedKeywords: [(Keyword, String)] = [
            (.as, "as"),
            (.break, "break"),
            (.class, "class"),
            (.catch, "catch"),
            (.continue, "continue"),
            (.data, "data"),
            (.do, "do"),
            (.else, "else"),
            (.false, "false"),
            (.dynamic, "dynamic"),
            (.enum, "enum"),
            (.external, "external"),
            (.for, "for"),
            (.fun, "fun"),
            (.if, "if"),
            (.infix, "infix"),
            (.in, "in"),
            (.is, "is"),
            (.import, "import"),
            (.interface, "interface"),
            (.finally, "finally"),
            (.null, "null"),
            (.operator, "operator"),
            (.object, "object"),
            (.package, "package"),
            (.return, "return"),
            (.super, "super"),
            (.this, "this"),
            (.typealias, "typealias"),
            (.throw, "throw"),
            (.true, "true"),
            (.try, "try"),
            (.val, "val"),
            (.var, "var"),
            (.while, "while"),
            (.when, "when"),
            (.sealed, "sealed"),
            (.inner, "inner"),
            (.reified, "reified"),
            (.open, "open"),
            (.private, "private"),
            (.public, "public"),
            (.protected, "protected"),
            (.internal, "internal"),
            (.override, "override"),
            (.final, "final"),
            (.abstract, "abstract"),
            (.suspend, "suspend"),
            (.inline, "inline"),
            (.expect, "expect"),
            (.actual, "actual"),
            (.constructor, "constructor"),
            (.companion, "companion"),
            (.annotation, "annotation"),
            (.const, "const"),
            (.crossinline, "crossinline"),
            (.lateinit, "lateinit"),
            (.noinline, "noinline"),
            (.tailrec, "tailrec"),
            (.vararg, "vararg"),
            (.value, "value"),
        ]

        for (keyword, expected) in expectedKeywords {
            #expect(keyword.rawValue == expected, "Keyword.\(expected) rawValue mismatch")
        }
    }

    @Test
    func testKeywordInitFromRawValueRoundTrips() {
        let allRawValues = [
            "as", "break", "class", "catch", "continue", "data", "do", "else",
            "false", "dynamic", "enum", "external", "for", "fun", "if", "infix",
            "in", "is", "import", "interface", "finally", "null", "operator",
            "object", "package", "return", "super", "this", "typealias", "throw",
            "true", "try", "val", "var", "while", "when", "sealed", "inner",
            "reified", "open", "private", "public", "protected", "internal",
            "override", "final", "abstract", "suspend", "inline", "expect",
            "actual", "constructor", "companion", "annotation", "const",
            "crossinline", "lateinit", "noinline", "tailrec", "vararg", "value",
        ]

        for raw in allRawValues {
            let keyword = Keyword(rawValue: raw)
            #expect(keyword != nil, "Keyword(rawValue: \"\(raw)\") should not be nil")
            #expect(keyword?.rawValue == raw)
        }
    }

    @Test
    func testKeywordInitFromInvalidRawValueReturnsNil() {
        #expect(Keyword(rawValue: "notAKeyword") == nil)
        #expect(Keyword(rawValue: "") == nil)
        #expect(Keyword(rawValue: "FUN") == nil)
    }

    @Test
    func testKeywordTokenKindEquality() {
        let allKeywords: [Keyword] = [
            .as, .break, .class, .catch, .continue, .data, .do, .else,
            .false, .dynamic, .enum, .external, .for, .fun, .if, .infix,
            .in, .is, .import, .interface, .finally, .null, .operator,
            .object, .package, .return, .super, .this, .typealias, .throw,
            .true, .try, .val, .var, .while, .when, .sealed, .inner,
            .reified, .open, .private, .public, .protected, .internal,
            .override, .final, .abstract, .suspend, .inline, .expect,
            .actual, .constructor, .companion, .annotation, .const,
            .crossinline, .lateinit, .noinline, .tailrec, .vararg, .value,
        ]

        for keyword in allKeywords {
            let kind = TokenKind.keyword(keyword)
            #expect(kind == TokenKind.keyword(keyword))
        }

        // Different keywords should not be equal
        #expect(TokenKind.keyword(.fun) != TokenKind.keyword(.val))
        #expect(TokenKind.keyword(.class) != TokenKind.keyword(.interface))
    }

    // MARK: - SoftKeyword enum: all cases

    @Test
    func testSoftKeywordAllCasesRawValues() {
        let expectedSoftKeywords: [(SoftKeyword, String)] = [
            (.by, "by"),
            (.get, "get"),
            (.set, "set"),
            (.field, "field"),
            (.property, "property"),
            (.receiver, "receiver"),
            (.param, "param"),
            (.setparam, "setparam"),
            (.delegate, "delegate"),
            (.file, "file"),
            (.where, "where"),
            (.`init`, "init"),
            (.constructor, "constructor"),
            (.out, "out"),
            (.when, "when"),
        ]

        for (softKeyword, expected) in expectedSoftKeywords {
            #expect(softKeyword.rawValue == expected, "SoftKeyword.\(expected) rawValue mismatch")
        }
    }

    @Test
    func testSoftKeywordInitFromRawValueRoundTrips() {
        let allRawValues = [
            "by", "get", "set", "field", "property", "receiver",
            "param", "setparam", "delegate", "file", "where",
            "init", "constructor", "out", "when",
        ]

        for raw in allRawValues {
            let softKeyword = SoftKeyword(rawValue: raw)
            #expect(softKeyword != nil, "SoftKeyword(rawValue: \"\(raw)\") should not be nil")
            #expect(softKeyword?.rawValue == raw)
        }
    }

    @Test
    func testSoftKeywordInitFromInvalidRawValueReturnsNil() {
        #expect(SoftKeyword(rawValue: "notASoftKeyword") == nil)
        #expect(SoftKeyword(rawValue: "") == nil)
        #expect(SoftKeyword(rawValue: "GET") == nil)
    }

    @Test
    func testSoftKeywordTokenKindEquality() {
        let allSoftKeywords: [SoftKeyword] = [
            .by, .get, .set, .field, .property, .receiver,
            .param, .setparam, .delegate, .file, .where,
            .`init`, .constructor, .out, .when,
        ]

        for softKeyword in allSoftKeywords {
            let kind = TokenKind.softKeyword(softKeyword)
            #expect(kind == TokenKind.softKeyword(softKeyword))
        }

        // Different soft keywords should not be equal
        #expect(TokenKind.softKeyword(.get) != TokenKind.softKeyword(.set))
        #expect(TokenKind.softKeyword(.field) != TokenKind.softKeyword(.property))
    }
}
#endif

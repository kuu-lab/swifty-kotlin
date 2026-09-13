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
        #expect(block != .blockComment("/* other */"))
        #expect(shebang != .shebang("#!/bin/sh"))
    }

    @Test
    func testTokenKindMissingBacktickedIdentifierAndCharLiteral() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 1)

        #expect(Token(kind: .missing(expected: .keyword(.fun)), range: range).kind
            == .missing(expected: .keyword(.fun)))
        #expect(Token(kind: .backtickedIdentifier(interner.intern("myFun")), range: range).kind
            == .backtickedIdentifier(interner.intern("myFun")))
        #expect(Token(kind: .charLiteral(65), range: range).kind == .charLiteral(65))
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

    // MARK: - Keyword

    /// Spelling table for every `Keyword`. The `allCases` guard below is what
    /// keeps it honest: a new case added to the enum fails this test until it
    /// is listed here, rather than silently escaping the suite.
    private static let keywordSpellings: [(Keyword, String)] = [
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

    @Test
    func testKeywordSpellingsCoverEveryCaseAndRoundTrip() {
        #expect(
            Set(Self.keywordSpellings.map(\.0)) == Set(Keyword.allCases),
            "keywordSpellings is out of sync with Keyword.allCases"
        )
        for (keyword, spelling) in Self.keywordSpellings {
            #expect(keyword.rawValue == spelling, "Keyword.\(keyword) rawValue mismatch")
            #expect(Keyword(rawValue: spelling) == keyword, "Keyword(rawValue: \"\(spelling)\") round-trip failed")
        }
    }

    @Test
    func testKeywordInitFromInvalidRawValueReturnsNil() {
        #expect(Keyword(rawValue: "notAKeyword") == nil)
        #expect(Keyword(rawValue: "") == nil)
        #expect(Keyword(rawValue: "FUN") == nil)
    }

    @Test
    func testDistinctKeywordsProduceDistinctTokenKinds() {
        #expect(TokenKind.keyword(.fun) != TokenKind.keyword(.val))
        #expect(TokenKind.keyword(.class) != TokenKind.keyword(.interface))
    }

    // MARK: - SoftKeyword

    /// See `keywordSpellings` for why the `allCases` guard matters here.
    private static let softKeywordSpellings: [(SoftKeyword, String)] = [
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
        (.context, "context"),
        (.where, "where"),
        (.`init`, "init"),
        (.constructor, "constructor"),
        (.out, "out"),
        (.when, "when"),
    ]

    @Test
    func testSoftKeywordSpellingsCoverEveryCaseAndRoundTrip() {
        #expect(
            Set(Self.softKeywordSpellings.map(\.0)) == Set(SoftKeyword.allCases),
            "softKeywordSpellings is out of sync with SoftKeyword.allCases"
        )
        for (softKeyword, spelling) in Self.softKeywordSpellings {
            #expect(softKeyword.rawValue == spelling, "SoftKeyword.\(softKeyword) rawValue mismatch")
            #expect(
                SoftKeyword(rawValue: spelling) == softKeyword,
                "SoftKeyword(rawValue: \"\(spelling)\") round-trip failed"
            )
        }
    }

    @Test
    func testSoftKeywordInitFromInvalidRawValueReturnsNil() {
        #expect(SoftKeyword(rawValue: "notASoftKeyword") == nil)
        #expect(SoftKeyword(rawValue: "") == nil)
        #expect(SoftKeyword(rawValue: "GET") == nil)
    }

    @Test
    func testDistinctSoftKeywordsProduceDistinctTokenKinds() {
        #expect(TokenKind.softKeyword(.get) != TokenKind.softKeyword(.set))
        #expect(TokenKind.softKeyword(.field) != TokenKind.softKeyword(.property))
    }
}
#endif

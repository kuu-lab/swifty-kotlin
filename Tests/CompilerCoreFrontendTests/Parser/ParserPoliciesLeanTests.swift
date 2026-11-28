#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func parserPolicyKeywordEncodingsMatchDeclarationAndLoopGrammar() {
        let parser = makePolicyParser("")
        let loops: Set<Keyword> = [.for, .while, .do]
        let modifiers: Set<Keyword> = [
            .public, .private, .internal, .protected, .open, .abstract, .sealed, .data, .annotation,
            .inner, .expect, .actual, .const, .lateinit, .override, .final, .crossinline, .noinline,
            .tailrec, .inline, .suspend, .operator, .infix, .external, .value, .vararg,
        ]
        let declarations = modifiers.union([.class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .companion])
        let companionNames = modifiers.union([.catch, .companion, .constructor, .dynamic, .enum, .finally, .import, .reified])
        for keyword in Keyword.allCases {
            let input = Comment(rawValue: keyword.rawValue)
            let kind = TokenKind.keyword(keyword)
            #expect(LeanParser.isLoopStart(parser, kind: kind) == loops.contains(keyword), input)
            #expect(LeanParser.isBareDeclarationStart(parser, kind: kind) == declarations.contains(keyword), input)
            #expect(LeanParser.isCompanionObjectName(parser, kind: kind) == companionNames.contains(keyword), input)
            #expect(LeanParser.canStartTypeName(parser, after: kind) == (keyword == .in), input)
        }
        for soft in SoftKeyword.allCases {
            let input = Comment(rawValue: soft.rawValue)
            let kind = TokenKind.softKeyword(soft)
            #expect(!LeanParser.isLoopStart(parser, kind: kind), input)
            #expect(LeanParser.isBareDeclarationStart(parser, kind: kind) == (soft == .context), input)
            #expect(LeanParser.isCompanionObjectName(parser, kind: kind) == (soft != .when), input)
            #expect(LeanParser.canStartTypeName(parser, after: kind) == (soft == .out), input)
        }
        let typeNameSymbols: Set<Symbol> = [.colon, .dot, .questionDot, .lessThan, .comma, .lParen, .arrow]
        for symbol in Symbol.allCases {
            let input = Comment(rawValue: symbol.rawValue)
            #expect(LeanParser.canStartTypeName(parser, after: .symbol(symbol)) == typeNameSymbols.contains(symbol), input)
            #expect(LeanParser.isBareDeclarationStart(parser, kind: .symbol(symbol)) == (symbol == .at), input)
        }
        #expect(!LeanParser.canStartTypeName(parser, after: nil))
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: [
        ("@Ann A", false), ("@Ann fun f() {}", true), ("context(x: Int) fun f() {}", true),
        ("context()", false), ("constructor() {}", true), ("private val x = 1", true),
        ("private context()", true), ("private name", false), ("import p.A", false),
    ])
    func parserPolicyEnumDeclarationDispatch(source: String, expected: Bool) {
        #expect(LeanParser.enumBodyStartsDeclaration(makePolicyParser(source)) == expected)
    }

    @Test
    func parserPolicyConstructorTailLeavesBoundaryAndEOF() {
        let cases: [(String, TokenKind)] = [
            ("\n: this(f(a; b)) {}", .symbol(.lBrace)),
            (": super(1); fun next() {}", .keyword(.fun)),
            (": super(1)\n;", .symbol(.semicolon)),
            ("\nthis(1) }", .symbol(.rBrace)),
            ("\nfun next() {}", .keyword(.fun)),
            (": this(f(1", .eof),
            ("", .eof),
        ]
        for (source, expected) in cases {
            let parser = makePolicyParser(source)
            let end = LeanParser.constructorTailCount(parser)
            #expect(end < parser.stream.tokens.count, Comment(rawValue: source))
            #expect(parser.stream.peek(end).kind == expected, Comment(rawValue: source))
            #expect(parser.stream.index == 0)
        }
    }

    @Test(arguments: [
        ("when", true), ("when (call(x))", true), ("when (x) + y", false),
        ("call(x)", false), ("foo(", false), ("`when` (x)", false),
    ])
    func parserPolicyWhenSubjectWalksBackOverParentheses(source: String, expected: Bool) throws {
        let parser = makePolicyParser(source)
        let last = try #require(parser.stream.tokens.last)
        let tokens = parser.stream.tokens.dropLast().map { SyntaxChild.token(parser.arena.appendToken($0)) }
        let detached = SyntaxChild.node(parser.arena.appendNode(kind: .statement, range: last.range, []))
        #expect(LeanParser.consumedTokensEndWithWhenSubject(parser, children: tokens + [detached]) == expected)
    }

    private func makePolicyParser(_ source: String) -> KotlinParser {
        let lexed = lex(source)
        return KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
    }
}
#endif

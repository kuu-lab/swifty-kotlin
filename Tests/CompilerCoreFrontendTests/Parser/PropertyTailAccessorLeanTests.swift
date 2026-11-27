#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("get() = x", true),
        ("Int set(v) {}", true),
        ("Int get(nested(x)): T", true),
        ("get((x): T", false),
        ("get() next = x", false),
        ("get()", false),
        ("get next() = x", false),
        ("a.get() {}", false),
        ("a?.get() {}", false),
        ("a::get() {}", false),
        ("= get() {}", false),
        (", set(v) {}", false),
        ("(get() {}", false),
        ("{ set(v) {}", false),
        ("[ get() {}", false),
        ("return get() {}", false),
        ("context get() {}", false),
        ("get set(v) {}", false),
        ("a.get() {}; T get() = value", true),
        ("`get`() = x", false),
    ])
    func propertyTailAccessorContracts(source: String, accepts: Bool) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        let children = propertyTailChildren(parser, tokens: Array(lexed.tokens.dropLast()), interleave: true)
        let last = parser.lastConsumedToken
        #expect(parser.propertyTailContainsAccessorHeader(children) == accepts)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == last)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func propertyTailAccessorUsesUnboundedMatchingParentheses() {
        let depth = KotlinParser.declarationLookaheadWorkLimit + 1
        let prefix = "get" + String(repeating: "(", count: depth) + "x"
        for missing in [0, 1] {
            let lexed = lex(prefix + String(repeating: ")", count: depth - missing) + " = x")
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            let children = propertyTailChildren(parser, tokens: Array(lexed.tokens.dropLast()), interleave: false)
            #expect(parser.propertyTailContainsAccessorHeader(children) == (missing == 0))
        }
    }

    private func propertyTailChildren(
        _ parser: KotlinParser, tokens: [Token], interleave: Bool
    ) -> [SyntaxChild] {
        let node = parser.arena.appendNode(kind: .statement, range: parser.invalidRange, [])
        return tokens.flatMap { token -> [SyntaxChild] in
            let child = SyntaxChild.token(parser.arena.appendToken(token))
            return interleave ? [.node(node), .token(TokenID(rawValue: -1)), child] : [child]
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func whenSubjectKeepsMultilineContextFunctionType() {
        let lexed = lex("(val item:\ncontext(String) () -> String = value)\nfun after() {}")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let group = parser.parseBalancedGroup(opening: .lParen, closing: .rParen, allowsWhenSubjectVariable: true)
        let tokens = parser.arena.children(of: group).compactMap { child -> TokenKind? in
            guard case let .token(id) = child else { return nil }
            return parser.arena.token(id)?.kind
        }
        #expect(tokens.contains(.symbol(.assign)))
        #expect(tokens.last == .symbol(.rParen))
        #expect(parser.stream.peek().kind == .keyword(.fun))
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

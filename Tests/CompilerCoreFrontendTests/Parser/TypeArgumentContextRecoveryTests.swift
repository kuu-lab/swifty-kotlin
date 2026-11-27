@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: ["context", "context(receiver: R)"])
    func unclosedTypeArgumentsPreserveModifierBeforeContext(context: String) {
        let lexed = lex("<T\nprivate \(context)\nfun next() {}")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.modifierDeclarationLookahead[2] = false
        _ = parser.parseTypeArguments()

        #expect(parser.stream.index == 2)
        #expect(parser.stream.peek().kind == .keyword(.private))
        #expect(parser.modifierDeclarationLookahead == [2: false])
        #expect(lexed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0005"])
        #expect(lexed.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[2].range)
    }

    @Test
    func bareContextWithoutOpeningParenthesisRemainsInTypeArguments() {
        let lexed = lex("<T\ncontext?>")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.parseTypeArguments()

        #expect(parser.stream.atEOF())
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: ["class", "private class"])
    func unclosedTypeArgumentsLeaveFollowingClassAtTheBoundary(declaration: String) {
        let lexed = lex("<T\n\(declaration) Next {}")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.parseTypeArguments()

        #expect(parser.stream.index == 2)
        #expect(lexed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0005"])
        #expect(lexed.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[2].range)
    }
}

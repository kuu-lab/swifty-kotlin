#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func typeArgumentOffsetIgnoresCloseInsideTemplateInterpolation() throws {
        let lexed = lex(#"anchor skip <"${a > b}"> tail"#)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()
        let interpolationStart = try #require(lexed.tokens.firstIndex { $0.kind == .templateExprStart })
        let interpolationEnd = try #require(lexed.tokens.firstIndex { $0.kind == .templateExprEnd })
        let comparison = try #require(lexed.tokens.firstIndex { $0.kind == .symbol(.greaterThan) })
        try #require(interpolationStart < comparison && comparison < interpolationEnd)

        let end = parser.offsetPastTypeArguments(from: 1)

        #expect(parser.stream.peek(end) == lexed.tokens[lexed.tokens.count - 2])
        #expect(parser.stream.index == 1)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

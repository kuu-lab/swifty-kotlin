#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [(":", true), ("?.", true), ("->", true), ("in", true), ("out", true), ("=", false), ("", false)])
    func typeNameStartAcceptsKotlinHeaderTokens(source: String, expected: Bool) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        #expect(LeanParser.canStartTypeName(parser, after: parser.stream.peek().kind) == expected)
        #expect(!LeanParser.canStartTypeName(parser, after: nil))
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

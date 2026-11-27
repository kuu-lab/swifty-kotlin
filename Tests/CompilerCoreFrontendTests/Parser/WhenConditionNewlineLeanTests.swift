#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [("!is T", true), ("!in xs", true), ("!flag", false), ("?.member", true), ("-1", false)])
    func whenConditionNewlinePreservesCompoundOperators(source: String, expected: Bool) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        #expect(LeanParser.whenConditionContinuesAfterLineBreak(parser, kind: parser.stream.peek().kind) == expected)
        #expect(parser.stream.index == 0)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [("name@", true), ("context@", true), ("`when`@", true), ("when@", false), ("name()", false), ("@", false)])
    func labelStartRequiresANameFollowedByAtSign(source: String, expected: Bool) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        #expect(parser.isLabelStart == expected)
        #expect(parser.stream.index == 0)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

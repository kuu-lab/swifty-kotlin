#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("@", true), ("context", true), ("private", true), ("package", true), ("enum", true),
        ("val", true), ("object", true), ("import", false), ("constructor", false), ("`context`", false),
    ])
    func bareDeclarationStartPreservesContextualAndDirectiveTokens(source: String, expected: Bool) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        #expect(parser.isDeclarationStart(parser.stream.peek().kind) == expected)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

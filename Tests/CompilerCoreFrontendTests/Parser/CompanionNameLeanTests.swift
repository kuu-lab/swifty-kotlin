#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("Named", true), ("`when`", true), ("get", true), ("private", true), ("enum", true),
        ("reified", true), ("import", true), ("fun", false), ("when", false), ("", false),
    ])
    func companionObjectNamePreservesContextualKeywords(source: String, expected: Bool) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        #expect(LeanParser.isCompanionObjectName(parser, kind: parser.stream.peek().kind) == expected)
        #expect(!LeanParser.isCompanionObjectName(parser, kind: .softKeyword(.when)))
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

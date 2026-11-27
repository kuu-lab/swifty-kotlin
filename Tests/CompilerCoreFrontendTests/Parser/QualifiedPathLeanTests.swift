#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("", false, false, 0),
        ("foo.bar", false, false, 3),
        ("foo.*", true, false, 3),
        ("foo.*", false, false, 2),
        ("*", true, true, 1),
        ("*", false, true, 0),
        ("\n*", true, true, 1),
        ("foo\n.*", true, true, 1),
        ("foo.\nbar", false, false, 2),
        ("\nfoo.bar", false, false, 3),
        ("foo as Alias", true, true, 1),
        ("foo as Alias", false, false, 1),
        ("as Alias", true, true, 0),
        ("foo.`as`", true, true, 3),
        ("foo\nval next", false, false, 1),
        ("\nprivate next", false, false, 0),
        ("\nprivate@ next", false, false, 1),
        ("import", false, false, 1),
        ("\nimport", false, false, 0),
        ("foo }", true, true, 1),
        ("foo.\n*", true, true, 2),
    ])
    func qualifiedPathLeavesBoundary(source: String, allowWildcard: Bool, stopAtAs: Bool, consumed: Int) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        #expect(LeanParser.qualifiedPathCount(parser, allowImportWildcard: allowWildcard, stopAtAs: stopAtAs) == consumed)
        #expect(parser.stream.index == 0)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

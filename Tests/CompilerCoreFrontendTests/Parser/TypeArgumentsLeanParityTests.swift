#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("<T>", true), ("<Map<K, V>>", true), ("<T,>", true), ("<in T>", true), ("<T", true),
        ("<>", false), ("<T,, U>", false), ("<in>", false), ("<T, out>", false), ("Plain", false)
    ])
    func declarationTypeArgumentStart(source: String, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()

        #expect(parser.canStartTypeArgumentsInternal(hasAnchorToken: true) == accepts)
        #expect(!parser.canStartTypeArgumentsInternal(hasAnchorToken: false))
        #expect(parser.stream.index == 1)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }
}
#endif

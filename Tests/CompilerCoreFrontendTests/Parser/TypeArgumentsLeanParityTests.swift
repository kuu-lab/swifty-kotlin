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

    @Test(arguments: ["<Map<K>> tail", "<T(fn(a > b))> tail", "<T[x > y]> tail", "<T{a > b}> tail", "<T"])
    func typeArgumentOffsetPreservesExpressionGroups(source: String) {
        let lexed = lex("anchor skip " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()

        let end = parser.offsetPastTypeArguments(from: 1)
        #expect(parser.stream.peek(end) == lexed.tokens[source.hasSuffix("tail") ? lexed.tokens.count - 2 : lexed.tokens.count - 1])
        #expect(parser.stream.index == 1)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }
}
#endif

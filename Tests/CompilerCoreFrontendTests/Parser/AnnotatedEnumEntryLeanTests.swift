#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("@A @pkg.Tag<T>(1) RED", true),
        ("@A @B `context`", true),
        ("@A get", true),
        ("@A context", false),
        ("@A private fun declared()", false),
        ("@A , RED", false),
        ("@A @field: , RED", false),
        ("@A @B( [1] RED", false),
        ("@A @B<T RED", false),
        ("@A @B", false),
        ("RED", false),
    ])
    func annotatedEnumEntryLookaheadContracts(source: String, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        #expect(LeanParser.enumEntryStartsAfterLeadingAnnotations(parser) == accepts)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func annotatedEnumEntriesAndFollowingMembersStaySeparate() {
        let parsed = parse("""
        enum class Color {
            @A @B(1) RED,
            @pkg.C GREEN;
            @D fun channel() = 1
        }
        """)
        #expect(parsed.arena.nodes.filter { $0.kind == .enumEntry }.count == 2)
        #expect(parsed.arena.nodes.filter { $0.kind == .funDecl }.count == 1)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

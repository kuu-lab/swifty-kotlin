#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("constructor()", true),
        ("constructor (", true),
        ("@A private @pkg.B<T>(1) actual constructor(val x: Int)", true),
        ("@A private constructor", false),
        ("@A constructor<T>()", false),
        ("@A `constructor`()", false),
        ("@A Other constructor()", false),
        ("private context(x: T) constructor()", false),
        ("@A @field: , constructor()", false),
        ("@A @B(1 constructor()", false),
        ("@A @B<T constructor()", false),
        ("private @A", false),
        ("()", false),
    ])
    func primaryConstructorHeaderLookaheadContracts(source: String, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        #expect(LeanParser.startsPrimaryConstructorHeader(parser) == accepts)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func primaryConstructorLookaheadKeepsFollowingDeclarationSeparate() {
        let parsed = parse("""
        class Box @A private @B(1) constructor(val value: Int)
        fun next() = 0
        """)
        #expect(parsed.arena.nodes.filter { $0.kind == .classDecl }.count == 1)
        #expect(parsed.arena.nodes.filter { $0.kind == .funDecl }.count == 1)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

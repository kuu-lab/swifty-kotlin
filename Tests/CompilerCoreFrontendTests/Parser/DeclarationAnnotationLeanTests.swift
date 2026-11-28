#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("@field: pkg.Tag<Outer<Inner>>> tail", .symbol(.greaterThan)),
        ("@Tag<(>) [>] {>}>> tail", .symbol(.greaterThan)),
        (#"@Tag<"${a > b}">> tail"#, .symbol(.greaterThan)),
        ("@field: <T>> tail", .symbol(.greaterThan)),
        ("@Tag<Outer<Inner>", .eof),
        ("@Tag< (> ", .eof),
        ("@pkg.", .symbol(.dot)),
        ("@field:", .eof),
        ("@field: pkg.Tag<T>(1) > tail", .symbol(.greaterThan)),
    ] as [(String, TokenKind)])
    func declarationAnnotationConsumesExactlyThePrefix(source: String, next: TokenKind) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        parser.consumeLeadingPrefix(.annotations, into: &children, range: &range)
        #expect(parser.stream.peek().kind == next)
        let prefix = Array(lexed.tokens[1..<parser.stream.index])
        #expect(parser.arena.tokens == prefix)
        #expect(children.count == prefix.count)
        #expect(parser.lastConsumedToken == prefix.last)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }
}
#endif

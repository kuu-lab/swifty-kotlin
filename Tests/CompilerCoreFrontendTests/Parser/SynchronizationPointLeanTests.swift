#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("", false, 0),
        ("", true, 0),
        ("} next val value", false, 1),
        ("}\n} next", false, 1),
        ("}", false, 1),
        ("} next", true, 0),
        ("val value", false, 0),
        (";", true, 0),
        ("junk\nnext", true, 1),
        ("junk\nnext", false, 2),
        ("junk ; next", true, 1),
        ("junk ; next", false, 3),
        ("junk } next", true, 1),
        ("junk } next", false, 3),
        ("junk catch e", true, 1),
        ("junk finally {}", true, 1),
        ("junk else next", true, 1),
        ("junk enum class Entry", false, 2),
        ("junk companion object Member", false, 2),
        ("junk\nprivate val value", false, 2),
        ("junk import path", false, 1),
    ])
    func recoveryStopsAtExpectedToken(source: String, inBlock: Bool, skipped: Int) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        parser.skipToSynchronizationPoint(inBlock: inBlock, into: &children, range: &range)

        #expect(parser.stream.index == skipped)
        #expect(parser.stream.peek() == lexed.tokens[skipped])
        #expect(children.count == skipped)
        if skipped == 0 {
            #expect(range.value == nil)
            #expect(lexed.diagnostics.diagnostics.isEmpty)
        } else {
            #expect(range.value == SourceRange(start: lexed.tokens[0].range.start, end: lexed.tokens[skipped - 1].range.end))
            #expect(lexed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0006"])
            #expect(lexed.diagnostics.diagnostics.map(\.message) == ["Skipped \(skipped) unexpected token(s)."])
        }
    }
}
#endif

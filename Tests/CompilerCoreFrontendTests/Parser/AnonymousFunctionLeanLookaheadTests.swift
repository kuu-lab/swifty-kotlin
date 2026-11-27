#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func anonymousFunctionLookaheadContracts() {
        let cases = [
            ("fun (x: T) {}", true),
            ("fun <T> (x: T) {}", true),
            ("fun T.(x: T) {}", true),
            ("fun (T).(x: T) {}", true),
            ("fun named(x: T) {}", false),
            ("fun (T).named(x: T) {}", false),
            ("fun <T> (T)?.named(x: T) {}", false),
            ("fun ; (x: T)", false),
            ("fun = (x: T)", false),
            ("val (x: T)", false),
            ("fun", false),
            ("fun " + String(repeating: "T ", count: 197) + ". (", true),
            ("fun " + String(repeating: "T ", count: 198) + ". (", false),
        ]
        for (source, expected) in cases {
            let parser = makeAnonymousLookaheadParser(source)
            #expect(parser.isAnonymousFunctionExpressionStart(at: 1) == expected, "\(source.prefix(100))")
            #expect(parser.stream.index == 1)
            #expect(parser.diagnostics.diagnostics.isEmpty)
        }
    }

    private func makeAnonymousLookaheadParser(_ source: String) -> KotlinParser {
        let lexed = lex("prefix anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()
        return parser
    }
}
#endif

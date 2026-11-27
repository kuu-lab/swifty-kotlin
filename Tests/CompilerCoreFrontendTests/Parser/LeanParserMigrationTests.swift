#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func lookaheadContracts() {
        let angles: [(String, Int)] = [
            ("< T < U > > tail", 6),
            ("< ( > ) [ > ] { > } > tail", 11),
            ("< T < U >", 5),
            ("< T >", 3),
        ]
        for (source, end) in angles {
            let (parser, offset) = lookaheadParser(source)
            #expect(parser.offsetPastTypeArguments(from: offset) == offset + end)
        }

        let parens: [(String, Int?, Int)] = [
            ("( ( T ) ) tail", nil, 5),
            ("( T )", 3, 3),
            ("( T )", 2, 0),
            ("( T", 2, 0),
            ("( T", 3, 2),
            ("( T )", 0, 0),
            ("( T )", -1, 0),
        ]
        for (source, limit, end) in parens {
            let (parser, offset) = lookaheadParser(source)
            #expect(parser.offsetPastBalancedGroup(
                from: offset, maxDistance: limit
            ) == offset + end)
        }

        let annotations: [(String, Int?)] = [
            ("@ A tail", 2),
            ("@ field : a . B < T > ( ( 1 ) ) tail", 14),
            ("@ : T", nil),
            ("@ field :", nil),
            ("@ A (", 3),
            ("@ A < T", 4),
        ]
        for (source, end) in annotations {
            let (parser, offset) = lookaheadParser(source)
            #expect(parser.offsetPastAnnotationPrefix(from: offset) == end.map { offset + $0 })
        }

        let defaults: [(String, Bool)] = [
            ("< T > ( x )", true),
            ("< T > { x }", true),
            ("< T > x", false),
            ("< T , , U > ( x )", false),
            ("< T", false),
            ("< " + String(repeating: "T ", count: 4094) + "> ( x )", true),
            ("< " + String(repeating: "T ", count: 4095) + "> ( x )", false),
        ]
        for (source, starts) in defaults {
            let (parser, _) = lookaheadParser(source, advanceToInput: true)
            #expect(LeanParser.valueParameterDefaultStartsTypeArguments(parser) == starts)
            parser.lastConsumedToken = nil
            #expect(!LeanParser.valueParameterDefaultStartsTypeArguments(parser))
        }
    }

    @Test
    func balancedGroupContracts() {
        let cases: [(source: String, parameters: Bool, whenSubject: Bool, consumed: Int, warning: Bool)] = [
            ("( a [ 1 { 2 } ] ) tail", false, false, 9, false),
            ("(\nval subject: T = value ) tail", false, true, 8, false),
            ("( x: Any =\nfun () {}\nfun after() {}", true, false, 10, true),
            ("( x: Int\nval after = 1", true, false, 4, true),
            ("( [ )", false, false, 3, true),
            ("missing", false, false, 0, false),
        ]
        for fixture in cases {
            let lexed = lex("prefix anchor " + fixture.source)
            let parser = groupParser(lexed.tokens, interner: lexed.interner)
            let start = parser.stream.index
            let node = parser.parseBalancedGroup(
                opening: .lParen, closing: .rParen,
                allowsValueParameters: fixture.parameters, allowsWhenSubjectVariable: fixture.whenSubject
            )
            let end = start + fixture.consumed
            #expect(parser.stream.index == end, "\(fixture.source)")
            #expect(parser.arena.node(node).kind == .statement)
            #expect(parser.arena.tokens == Array(lexed.tokens[start..<end]))
            #expect(parser.diagnostics.diagnostics.map(\.code) == (fixture.warning ? ["KSWIFTK-PARSE-0004"] : []))
            if fixture.warning {
                #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[end].range)
            }
        }
    }

    private func groupParser(_ tokens: [Token], interner: StringInterner) -> KotlinParser {
        let parser = KotlinParser(tokens: tokens, interner: interner, diagnostics: DiagnosticEngine())
        _ = parser.stream.advance()
        parser.lastConsumedToken = parser.stream.advance()
        return parser
    }

    private func lookaheadParser(_ source: String, advanceToInput: Bool = false) -> (KotlinParser, Int) {
        let lexed = lex("prefix anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()
        if advanceToInput {
            parser.lastConsumedToken = parser.stream.advance()
        }
        return (parser, advanceToInput ? 0 : 1)
    }
}
#endif

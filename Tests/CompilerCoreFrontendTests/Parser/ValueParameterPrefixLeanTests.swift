#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func valueParameterPrefixContracts() {
        let cases: [(source: String, end: TokenKind)] = [
            ("@param: pkg.A<T>((1)) private val suspend: T )", .eof),
            ("@A private: T )", .eof),
            ("@A var `when`: T )", .eof),
            ("@param: ( T )", .symbol(.at)),
            ("@ ( T )", .symbol(.at)),
            ("@A( T\nfun next() {}", .symbol(.at)),
            ("@A<T", .symbol(.at)),
            ("@A . : T )", .symbol(.at)),
        ]
        for fixture in cases {
            let lexed = lex("(\n" + fixture.source)
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen, allowsValueParameters: true)
            #expect(parser.stream.peek().kind == fixture.end, "\(fixture.source)")
            if fixture.end == .eof {
                #expect(parser.diagnostics.diagnostics.isEmpty)
            } else {
                #expect(parser.stream.index == 1)
                #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
                #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[1].range)
            }
        }
    }

    @Test
    func valueParameterPrefixBudgetContracts() {
        let limit = KotlinParser.declarationLookaheadWorkLimit
        let lastDot = 3 + 2 * (limit - 1)
        let cases: [(dots: Int, suffix: String, budgetIndex: Int?, closes: Bool)] = [
            (limit - 2, " p: T )", nil, true),
            (limit - 1, "( (1) ) p: T )", lastDot + 5, false),
            (limit, " p: T )", lastDot, false),
            (limit - 1, "( T\nfun next() {}", nil, false),
        ]
        for fixture in cases {
            let source = "(\n@A" + String(repeating: " . X", count: fixture.dots) + fixture.suffix
            let lexed = lex(source)
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen, allowsValueParameters: true)
            if fixture.closes {
                #expect(parser.stream.atEOF())
                #expect(parser.diagnostics.diagnostics.isEmpty)
            } else {
                #expect(parser.stream.index == 1)
                let codes = parser.diagnostics.diagnostics.map(\.code)
                if let index = fixture.budgetIndex {
                    #expect(codes == ["KSWIFTK-PARSE-0007", "KSWIFTK-PARSE-0004"])
                    #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[index].range)
                } else {
                    #expect(codes == ["KSWIFTK-PARSE-0004"])
                }
                #expect(parser.diagnostics.diagnostics.last?.primaryRange == lexed.tokens[1].range)
            }
        }
    }
}
#endif

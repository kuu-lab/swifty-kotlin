#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("@field: pkg.A<T>((1), [2]) tail", .complete(18)),
        ("@field: (", .incomplete(3)),
        ("@A(value", .incomplete(4)),
        ("@A(value\nfun later()", .incomplete(4)),
        ("@A([\nfun nested()]) tail", .complete(10)),
        ("@A(ref::\nclass Named) tail", .complete(8)),
    ] as [(String, LeanParser.AnnotationPrefixEnd)])
    func annotationPrefixEndsAtRecoveryOrFollowingToken(source: String, end: LeanParser.AnnotationPrefixEnd) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()
        #expect(LeanParser.annotationPrefixEnd(parser, from: 0) == end)
        #expect(parser.stream.index == 1)
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.genuineDeclarationLookahead.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func annotationPrefixBudgetReportsFirstUnchargedToken() {
        let limit = KotlinParser.declarationLookaheadWorkLimit
        for count in [limit - 2, limit - 1] {
            let lexed = lex("@A(" + String(repeating: "1 ", count: count) + ") tail")
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            let closing = 3 + count
            if count == limit - 2 {
                #expect(LeanParser.annotationPrefixEnd(parser, from: 0) == .complete(closing + 1))
                #expect(parser.diagnostics.diagnostics.isEmpty)
            } else {
                #expect(LeanParser.annotationPrefixEnd(parser, from: 0) == .overBudget(closing))
                #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0007"])
                #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[closing].range)
            }
            #expect(parser.stream.index == 0)
        }
    }
}
#endif

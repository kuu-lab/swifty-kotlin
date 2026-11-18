#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct GenericAnnotationParsingTests {
    @Test
    func declarationPrefixConsumesGenericAnnotationTypeArguments() {
        let parsed = parse("""
        annotation class TA<T>
        @TA<Int> class C
        @TA<Date, DateParceler>() val parcelled: Int
        fun after() {}
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.filter { $0.kind == .classDecl }.count == 2)
        #expect(parsed.arena.nodes.filter { $0.kind == .propertyDecl }.count == 1)
        #expect(parsed.arena.nodes.filter { $0.kind == .funDecl }.count == 1)
        #expect(parsed.arena.nodes.filter { $0.kind == .typeArgs }.count == 1)
    }

    @Test
    func annotationParserSkipsTypeArgumentsBeforeArguments() throws {
        let (tokens, interner, diagnostics) = lex("@TA<Date, DateParceler>() val parcelled: Int")
        #expect(!diagnostics.hasError)

        let parsed = try #require(AnnotationParsingSupport.parseAnnotation(
            from: tokens,
            start: 0,
            interner: interner,
            allowUseSiteTarget: true
        ))

        #expect(parsed.annotation.name == "TA")
        #expect(parsed.annotation.arguments.isEmpty)
        #expect(tokens[parsed.nextIndex].kind == .keyword(.val))
        #expect(parsed.annotation.constructionTokens?.contains { $0.kind == .symbol(.lessThan) } == true)
        #expect(parsed.annotation.constructionTokens?.contains { $0.kind == .symbol(.rParen) } == true)
    }
}
#endif

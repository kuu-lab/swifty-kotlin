#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("@field: pkg.A<T>((1), [2]) private context(x: T) fun named()", true),
        ("@A(\nfun named()", true),
        ("@field: (", true),
        ("@A(\nfun () {}) identifier", false),
        ("context(x: T) { value }", false),
        ("private object : T {}", false),
        ("private companion()", false),
        ("value suspend fun named()", false),
        ("value class Named", true),
    ])
    func genuineDeclarationPrefixContracts(source: String, declares: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        #expect(parser.declarationPrefixVerdict(at: 1) == (declares ? .declaration : .notDeclaration))
        #expect(parser.stream.index == 0)
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func genuineDeclarationCacheAndBudgetContracts() {
        let value = lex("value suspend fun named()")
        let parser = KotlinParser(tokens: value.tokens, interner: value.interner, diagnostics: value.diagnostics)
        #expect(parser.declarationPrefixVerdict(at: 0) == .notDeclaration)
        #expect(parser.genuineDeclarationLookahead == [0: false, 2: true])
        #expect(parser.declarationPrefixVerdict(at: 1) == .declaration)
        #expect(parser.genuineDeclarationLookahead == [0: false, 1: true, 2: true])

        let label = lex("label@ fun named()")
        let labeled = KotlinParser(tokens: label.tokens, interner: label.interner, diagnostics: label.diagnostics)
        labeled.genuineDeclarationLookahead[0] = true
        #expect(labeled.declarationPrefixVerdict(at: 0) == .notDeclaration)
        #expect(labeled.genuineDeclarationLookahead == [0: true])

        let limit = KotlinParser.declarationLookaheadWorkLimit
        let lexed = lex("anchor @A(" + String(repeating: "1, ", count: limit / 2) + ") fun next()")
        let bounded = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        #expect(bounded.declarationPrefixVerdict(at: 1) == .overBudget)
        #expect(bounded.genuineDeclarationLookahead == [1: true])
        #expect(bounded.declarationPrefixVerdict(at: 1) == .declaration)
        #expect(bounded.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0007"])
        #expect(bounded.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[limit + 2].range)
    }
}
#endif

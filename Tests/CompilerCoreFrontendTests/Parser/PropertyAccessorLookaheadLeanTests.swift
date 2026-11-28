#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("@A @pkg.Tag(1) private inline get(): List<T> = x", false, true),
        ("@A inline set(v) {}", false, true),
        ("private @A set", true, false),
        ("@A @field: , set", true, false),
        ("@A(1 get() = x", true, false),
        ("@A<T get() = x", true, false),
        ("get", true, true),
        ("get", false, false),
        ("private get", false, false),
        ("set;", true, true),
        ("set}", false, false),
        ("public inline set}", false, true),
        ("internal set\nnext", false, true),
        ("protected set next", false, false),
        ("inline set", false, false),
        ("get(): = x", false, true),
        ("get(): T\nfun next() = 1", true, false),
        ("get(): List<\nfun T> = x", false, true),
        ("`get`() = x", true, false),
    ])
    func propertyAccessorLookaheadContracts(source: String, allowsBodyless: Bool, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        parser.lastConsumedToken = parser.stream.advance()
        #expect(parser.isPropertyAccessorStart(allowsBodyless: allowsBodyless) == accepts)
        #expect(parser.stream.index == 1)
        #expect(parser.lastConsumedToken == lexed.tokens[0])
        #expect(parser.arena.tokens.isEmpty)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func propertyAccessorLookaheadBudgetAndDeclarationEffects() {
        for (head, length, tail) in [("get(", 62, ") = x"), ("get(): ", 60, " = x")] {
            for delta in [0, 1] {
                let lexed = lex(head + String(repeating: "T ", count: length + delta) + tail)
                let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
                #expect(parser.isPropertyAccessorStart(allowsBodyless: false) == (delta == 0))
            }
        }
        let lexed = lex("get(): T\n@A fun next() = 1")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        #expect(!parser.isPropertyAccessorStart(allowsBodyless: false))
        #expect(parser.genuineDeclarationLookahead == [5: true, 7: true])
        #expect(parser.diagnostics.diagnostics.isEmpty)

        let long = lex("get(): T\n" + String(repeating: "private ", count: KotlinParser.declarationLookaheadWorkLimit)
            + "fun next() = 1")
        let bounded = KotlinParser(tokens: long.tokens, interner: long.interner, diagnostics: long.diagnostics)
        #expect(!bounded.isPropertyAccessorStart(allowsBodyless: false))
        #expect(bounded.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0007"])
        #expect(bounded.diagnostics.diagnostics.first?.primaryRange
            == long.tokens[5 + KotlinParser.declarationLookaheadWorkLimit].range)
    }
}
#endif

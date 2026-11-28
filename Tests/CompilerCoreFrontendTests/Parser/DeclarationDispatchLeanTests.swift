#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func declarationDispatchChoosesNodeAfterPrefix() {
        let cases: [(String, SyntaxKind)] = [
            ("@Ann class C", .classDecl),
            ("@Ann object O", .objectDecl),
            ("@Ann interface I", .interfaceDecl),
            ("@Ann fun interface I", .interfaceDecl),
            ("@Ann context(x: Int) fun f() {}", .funDecl),
            ("@Ann val v = 1", .propertyDecl),
            ("@Ann var v = 1", .propertyDecl),
            ("@Ann typealias T = Int", .typeAliasDecl),
            ("@Ann enum class E { A }", .classDecl),
            ("@Ann enum `E` { A }", .classDecl),
            ("@Ann package p", .packageHeader),
            ("@Ann import p.Foo", .importHeader),
            ("@Ann constructor() {}", .constructorDecl),
            ("@Ann companion object", .objectDecl),
            ("@Ann companion { println(1) }", .statement),
            ("@Ann companion @Other object O", .objectDecl),
            ("@Ann enum fun f() {}", .funDecl),
        ]
        for (source, expected) in cases {
            let lexed = lex(source)
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            let node = parser.parseDeclaration()
            let input = Comment(rawValue: source)

            #expect(parser.arena.node(node).kind == expected, input)
            #expect(parser.stream.index == lexed.tokens.count - 1, input)
            #expect(parser.stream.peek().kind == .eof, input)
            #expect(!parser.arena.tokens.contains { $0.kind == .eof }, input)
            #expect(!lexed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0032" }, input)
        }
    }

    @Test(arguments: [
        ("get()", true, false), ("set(value)", true, false), ("@Ann get()", false, true),
        ("@Ann set(value)", false, true), ("@Ann `set`(value)", false, false)
    ])
    func declarationDispatchRecoveryDiagnosesOnlyPrefixedSoftAccessors(head: String, isCall: Bool, diagnoses: Bool) {
        let lexed = lex(head + "\nfun next() {}")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let node = parser.parseDeclaration()

        #expect(parser.arena.node(node).kind == (isCall ? .callExpr : .statement))
        #expect(parser.stream.peek().kind == .keyword(.fun))
        let diagnostics = lexed.diagnostics.diagnostics
        #expect(diagnostics.map(\.code) == (diagnoses ? ["KSWIFTK-PARSE-0002"] : []))
        if diagnoses {
            let accessor = lexed.tokens.first {
                $0.kind == .softKeyword(.get) || $0.kind == .softKeyword(.set)
            }
            #expect(diagnostics.first?.primaryRange == accessor?.range)
        }
    }
}
#endif

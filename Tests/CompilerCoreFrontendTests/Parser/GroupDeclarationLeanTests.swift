#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [false, true])
    func contextAfterModifiersInGroupsAndTypeArguments(declares: Bool) {
        let prefix = "T\nprivate inline context"
        let declaration = "(receiver: R) fun next()"
        let fixtures = [
            ("(" + prefix + (declares ? declaration : "? )"), false, "KSWIFTK-PARSE-0004"),
            ("<" + prefix + (declares ? declaration : "?>"), true, "KSWIFTK-PARSE-0005"),
        ]
        for (source, typeArguments, diagnostic) in fixtures {
            let lexed = lex(source)
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            if typeArguments {
                _ = parser.parseTypeArguments()
            } else {
                _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen)
            }

            #expect(parser.modifierDeclarationLookahead == [2: declares, 3: declares, 4: declares])
            if declares {
                #expect(parser.stream.index == 2)
                #expect(parser.arena.tokens == Array(lexed.tokens.prefix(2)))
                #expect(parser.diagnostics.diagnostics.map(\.code) == [diagnostic])
                #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[2].range)
            } else {
                #expect(parser.stream.atEOF())
                #expect(parser.diagnostics.diagnostics.isEmpty)
            }
        }
    }

    @Test
    func groupDeclarationLookaheadContracts() {
        let limit = KotlinParser.declarationLookaheadWorkLimit
        let lexed = lex("( T\n" + String(repeating: "private ", count: limit) + "T )")
        let modifierStart = 2
        let budgetIndex = modifierStart + limit

        let cold = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
        _ = cold.parseBalancedGroup(opening: .lParen, closing: .rParen)
        #expect(cold.stream.index == modifierStart)
        #expect(cold.modifierDeclarationLookahead == Dictionary(
            uniqueKeysWithValues: (modifierStart..<budgetIndex).map { ($0, true) }
        ))
        #expect(cold.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0007", "KSWIFTK-PARSE-0004"])
        #expect(cold.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[budgetIndex].range)
        #expect(cold.diagnostics.diagnostics.last?.primaryRange == lexed.tokens[modifierStart].range)

        let warm = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
        warm.modifierDeclarationLookahead[budgetIndex] = false
        _ = warm.parseBalancedGroup(opening: .lParen, closing: .rParen)
        #expect(warm.stream.atEOF())
        #expect(warm.modifierDeclarationLookahead == Dictionary(
            uniqueKeysWithValues: (modifierStart...budgetIndex).map { ($0, false) }
        ))
        #expect(warm.diagnostics.diagnostics.isEmpty)

        let ordinary = lex("( T\nprivate val v )")
        let terminal = KotlinParser(tokens: ordinary.tokens, interner: ordinary.interner, diagnostics: ordinary.diagnostics)
        _ = terminal.parseBalancedGroup(opening: .lParen, closing: .rParen)
        #expect(terminal.stream.index == modifierStart)
        #expect(terminal.modifierDeclarationLookahead == [modifierStart: true, modifierStart + 1: true])
        #expect(terminal.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])

        for (source, closes) in [("(\ncontext: T )", true), ("(\ncontext(x: T) fun f() )", false)] {
            let context = lex(source)
            let parser = KotlinParser(tokens: context.tokens, interner: context.interner, diagnostics: context.diagnostics)
            _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen)
            #expect(parser.stream.atEOF() == closes)
            #expect(parser.diagnostics.diagnostics.isEmpty == closes)
            #expect(parser.modifierDeclarationLookahead.isEmpty)
        }
    }
}
#endif

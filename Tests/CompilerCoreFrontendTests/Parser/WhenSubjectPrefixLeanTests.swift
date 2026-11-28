#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test
    func whenSubjectPrefixContracts() {
        let cases: [(subject: String, end: TokenKind)] = [
            ("val get = value )", .eof),
            ("val `when`: Array<(T = U)\nfun T> = value )", .eof),
            ("val item: List<(T = U)> =\nfun after() {}", .keyword(.fun)),
            ("val item:\nfun next() = value )", .keyword(.val)),
            ("val item:\n@A Int = value )", .keyword(.val)),
            ("val item:\nopen = value )", .eof),
            ("val item:\nprivate fun next() = value )", .keyword(.val)),
            ("val item: T, U = value )", .keyword(.val)),
            ("var item: T = value )", .keyword(.var)),
        ]
        for fixture in cases {
            let lexed = lex("(\n" + fixture.subject)
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen,
                                          allowsWhenSubjectVariable: true)
            #expect(parser.stream.peek().kind == fixture.end, "\(fixture.subject)")
            if fixture.end == .eof {
                #expect(parser.diagnostics.diagnostics.isEmpty)
            } else {
                #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
                #expect(parser.diagnostics.diagnostics.first?.primaryRange == parser.stream.peek().range)
            }
        }
    }

    @Test(arguments: [
        ("val item:\ncontext = value )", false),
        ("val item:\ncontext? = value )", false),
        ("val item: List<\ncontext(T)> = value )", false),
        ("val item: T\ncontext(receiver: R) fun next() = value )", true),
    ])
    func whenSubjectContextBoundaryUsesTheTypeCursor(subject: String, rejects: Bool) {
        let lexed = lex("(\n" + subject)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen, allowsWhenSubjectVariable: true)
        if rejects {
            #expect(parser.stream.index == 1)
            #expect(parser.stream.peek().kind == .keyword(.val))
            #expect(parser.arena.tokens == [lexed.tokens[0]])
            #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
            #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[1].range)
        } else {
            #expect(parser.stream.atEOF())
            #expect(parser.diagnostics.diagnostics.isEmpty)
        }
    }

    @Test(arguments: [
        ("context = value )", false),
        ("context? = value )", false),
        ("context(receiver: R) fun next() = value )", true),
    ])
    func whenSubjectContextAfterModifiers(subject: String, rejects: Bool) {
        let lexed = lex("(\nval item: T\nprivate inline " + subject)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen, allowsWhenSubjectVariable: true)

        #expect(parser.modifierDeclarationLookahead == [5: rejects, 6: rejects, 7: rejects])
        if rejects {
            #expect(parser.stream.index == 1)
            #expect(parser.arena.tokens == [lexed.tokens[0]])
            #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
            #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[1].range)
        } else {
            #expect(parser.stream.atEOF())
            #expect(parser.diagnostics.diagnostics.isEmpty)
        }
    }

    @Test
    func whenSubjectPrefixBudgetContracts() {
        let limit = KotlinParser.declarationLookaheadWorkLimit
        for typeLength in [limit - 1, limit] {
            let lexed = lex("(\nval subject: " + String(repeating: "T ", count: typeLength) + "= value )")
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
            _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen,
                                          allowsWhenSubjectVariable: true)
            if typeLength < limit {
                #expect(parser.stream.atEOF())
                #expect(parser.diagnostics.diagnostics.isEmpty)
            } else {
                let assignIndex = 4 + typeLength
                #expect(parser.stream.index == 1)
                #expect(lexed.tokens[assignIndex].kind == .symbol(.assign))
                #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0007", "KSWIFTK-PARSE-0004"])
                #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[assignIndex].range)
            }
        }

        let modifiers = String(repeating: "private ", count: limit)
        let lexed = lex("(\nval subject:\n" + modifiers + "fun next() = value )")
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen, allowsWhenSubjectVariable: true)
        let firstModifier = 4
        let exhaustedAt = firstModifier + limit
        #expect(parser.stream.index == 1)
        #expect(lexed.tokens[exhaustedAt].kind == .keyword(.fun))
        #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0007", "KSWIFTK-PARSE-0004"])
        #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[exhaustedAt].range)
        #expect(parser.modifierDeclarationLookahead[firstModifier] == true)
        #expect(parser.modifierDeclarationLookahead[exhaustedAt] == nil)
        #expect(parser.modifierDeclarationLookahead[1] == nil)
    }

    @Test
    func whenSubjectModifierProbeUsesTheTypeCursor() {
        let subjectStart = 1
        let firstModifier = 4
        let lastModifier = 5
        let terminal = 6
        for (type, declares) in [("private\ninline T", false), ("private\ninline fun next()", true)] {
            let lexed = lex("(\nval subject:\n" + type + " = value )")
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
            parser.modifierDeclarationLookahead[subjectStart] = !declares
            _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen, allowsWhenSubjectVariable: true)
            #expect(parser.modifierDeclarationLookahead == [
                subjectStart: !declares, firstModifier: declares, lastModifier: declares, terminal: declares,
            ])
            #expect(parser.stream.atEOF() == !declares)
            #expect(parser.diagnostics.diagnostics.map(\.code) == (declares ? ["KSWIFTK-PARSE-0004"] : []))
            if declares {
                #expect(parser.stream.index == subjectStart)
                #expect(parser.diagnostics.diagnostics.first?.primaryRange == lexed.tokens[subjectStart].range)
            }
        }

        let lexed = lex("(\nval subject:\nopen = value )")
        for cached in [false, true] {
            let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
            parser.modifierDeclarationLookahead[firstModifier] = cached
            _ = parser.parseBalancedGroup(opening: .lParen, closing: .rParen, allowsWhenSubjectVariable: true)
            #expect(parser.modifierDeclarationLookahead == [firstModifier: cached])
            #expect(parser.stream.atEOF() == !cached)
            #expect(parser.diagnostics.diagnostics.map(\.code) == (cached ? ["KSWIFTK-PARSE-0004"] : []))
        }
    }
}
#endif

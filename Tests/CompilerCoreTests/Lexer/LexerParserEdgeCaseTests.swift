#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LexerParserEdgeCaseTests {
    @Test
    func testLexerConsumesTriviaIdentifiersAndAllSymbols() {
        let source = """
        #!/usr/bin/env kotlin
        // line comment
        /* outer /* nested */ done */
        class `hello world` value by get set field receiver param setparam delegate file where init constructor out when
        && || == != <= >= += -= *= /= %= ++ -- ..< ?? ?. ?: ? !! :: => -> .. + - * / % ! = < > . , ; : ( ) [ ] { } @ #
        """

        let result = lex(source)
        let symbols = Set(result.tokens.compactMap { token -> Symbol? in
            if case let .symbol(symbol) = token.kind {
                return symbol
            }
            return nil
        })

        let expected: Set<Symbol> = [
            .ampAmp, .barBar, .equalEqual, .bangEqual, .lessOrEqual, .greaterOrEqual,
            .plusAssign, .minusAssign, .starAssign, .slashAssign, .percentAssign,
            .plusPlus, .minusMinus, .dotDotLt, .questionQuestion, .questionDot, .questionColon,
            .question, .bangBang, .doubleColon, .fatArrow, .arrow, .dotDot,
            .plus, .minus, .star, .slash, .percent, .bang, .assign,
            .lessThan, .greaterThan, .dot, .comma, .semicolon, .colon,
            .lParen, .rParen, .lBracket, .rBracket, .lBrace, .rBrace, .at, .hash,
        ]
        #expect(symbols == expected)

        #expect(result.tokens.contains { token in
            if case .backtickedIdentifier = token.kind { return true }
            return false
        })

        #expect(result.tokens.contains { token in
            if case .softKeyword(.where) = token.kind { return true }
            return false
        })

        #expect(!(result.diagnostics.hasError))
        #expect(result.tokens.first?.leadingTrivia.contains { piece in
            if case .shebang = piece { return true }
            return false
        } ?? false)
    }

    @Test
    func testLexerStringTemplateAndEscapeDiagnostics() {
        let source = """
        val a = \"ok\\n\\t\\r\\\"\\'\\\\\\$\"
        val b = \"value ${1 + 2} $name\"
        val c = \"\"\"raw ${name} block\"\"\"
        val d = \"bad\\q\"
        val e = \"bad unicode \\u{110000}\"
        val f = \"unterminated
        """

        let result = lex(source)
        let kinds = result.tokens.map(\.kind)

        #expect(kinds.contains(.stringQuote))
        #expect(kinds.contains(.rawStringQuote))
        #expect(kinds.contains(.templateExprStart))
        #expect(kinds.contains(.templateExprEnd))
        #expect(kinds.contains(.templateSimpleNameStart))
        #expect(kinds.contains { kind in
            if case .stringSegment = kind { return true }
            return false
        })

        let codes = Set(result.diagnostics.diagnostics.map(\.code))
        #expect(codes.contains("KSWIFTK-LEX-0002"))
        #expect(codes.contains("KSWIFTK-LEX-0003"))
        #expect(!(codes.isEmpty))
    }

    @Test
    func testLexerNumericAndCharLiteralsCoverErrorAndSuffixPaths() {
        let source = """
        0x1F 0X 0b101 0b 0o77 0o
        1_ 1.0 1. 1e 1e+2 10L 11f 12D
        'a' '\\n' '\\u0041' '\\u{1F600}' '\\q' 'x
        """

        let result = lex(source)

        #expect(result.tokens.contains { token in
            if case .intLiteral("0x1F") = token.kind { return true }
            return false
        })
        #expect(result.tokens.contains { token in
            if case .intLiteral("0b101") = token.kind { return true }
            return false
        })
        #expect(result.tokens.contains { token in
            if case .longLiteral("10L") = token.kind { return true }
            return false
        })
        #expect(result.tokens.contains { token in
            if case .floatLiteral("11f") = token.kind { return true }
            return false
        })
        #expect(result.tokens.contains { token in
            if case .doubleLiteral("12D") = token.kind { return true }
            return false
        })
        #expect(result.tokens.contains { token in
            if case .charLiteral(97) = token.kind { return true }
            return false
        })

        let codeCounts = Dictionary(grouping: result.diagnostics.diagnostics, by: \.code).mapValues(\.count)
        #expect((codeCounts["KSWIFTK-LEX-0002"] ?? 0) >= 1)
        #expect((codeCounts["KSWIFTK-LEX-0003"] ?? 0) >= 1)
        #expect((codeCounts["KSWIFTK-LEX-0006"] ?? 0) >= 1)
    }

    @Test
    func testParserParsesDeclarationsTypeArgsAndEmitsWarningsForBrokenInput() {
        let source = """
        package demo.pkg
        import kotlin.collections.*

        public inline class Box<T>(value: T)
        companion object C
        interface I
        object O
        typealias Alias = Int
        enum class E { A, B, C }
        fun <T> id(x: T) = x
        fun broken(
        fun ()
        package
        """

        let parsed = parse(source)
        let arena = parsed.arena
        let rootChildren = arena.children(of: parsed.root)
        #expect(!(rootChildren.isEmpty))

        let kinds = Set(arena.nodes.map(\.kind))
        #expect(kinds.contains(.packageHeader))
        #expect(kinds.contains(.importHeader))
        #expect(kinds.contains(.classDecl))
        #expect(kinds.contains(.objectDecl))
        #expect(kinds.contains(.funDecl))
        #expect(kinds.contains(.statement))
        #expect(kinds.contains(.typeArgs) || kinds.contains(.enumEntry))

        let warningCodes = Set(parsed.diagnostics.diagnostics.map(\.code))
        #expect(warningCodes.contains("KSWIFTK-PARSE-0002"))
        #expect(!(warningCodes.isEmpty))

        let parserForTypeArgs = KotlinParser(tokens: parsed.tokens, interner: parsed.interner, diagnostics: DiagnosticEngine())
        _ = parserForTypeArgs.parseFile()
        let trailingToken = parsed.tokens.first(where: { token in
            if case .keyword(.class) = token.kind { return true }
            return false
        }) ?? makeToken(kind: .keyword(.class))
        _ = parserForTypeArgs.canStartTypeArguments(after: trailingToken)
        _ = parserForTypeArgs.canStartTypeArguments(after: NodeID(rawValue: -1))
    }

    @Test
    func testLexerTemplateExpressionCoversNestedInvalidAndUnterminatedPaths() {
        let source = """
        val a = "${{1 + 2}}"
        val b = "${'a'}"
        val c = "${"inner"}"
        val d = "${\"\"\"raw\"\"\"}"
        val e = "${${1}}"
        val f = "${~}"
        val g = "${1 + "
        """

        let result = lex(source)
        let templateStarts = result.tokens.filter { $0.kind == .templateExprStart }
        let templateEnds = result.tokens.filter { $0.kind == .templateExprEnd }
        #expect(templateStarts.count >= 6)
        #expect(templateEnds.count >= 4)

        let codes = Set(result.diagnostics.diagnostics.map(\.code))
        #expect(codes.contains("KSWIFTK-LEX-0001"))
        #expect(codes.contains("KSWIFTK-LEX-0002"))
    }

    @Test
    func testParserCanStartTypeArgumentsLookaheadVariants() {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let anchor = makeToken(kind: .keyword(.fun))

        let parserA = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.lParen)),
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        #expect(parserA.canStartTypeArguments(after: anchor))

        let parserB = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .keyword(.in)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.comma)),
                makeToken(kind: .softKeyword(.out)),
                makeToken(kind: .identifier(interner.intern("R"))),
                makeToken(kind: .symbol(.comma)),
                makeToken(kind: .symbol(.star)),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.colon)),
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        #expect(parserB.canStartTypeArguments(after: anchor))

        let parserB2 = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .keyword(.in)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.comma)),
                makeToken(kind: .softKeyword(.out)),
                makeToken(kind: .identifier(interner.intern("R"))),
                makeToken(kind: .symbol(.comma)),
                makeToken(kind: .symbol(.star)),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.colon)),
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        #expect(!(parserB2.canStartTypeArguments(after: anchor)))

        let parserC = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.lParen)),
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        #expect(!(parserC.canStartTypeArguments(after: anchor)))

        let parserD = KotlinParser(
            tokens: [
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .symbol(.dot)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .symbol(.lParen)),
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        #expect(!(parserD.canStartTypeArguments(after: anchor)))

        let parserE = KotlinParser(
            tokens: [
                makeToken(kind: .keyword(.fun)),
                makeToken(kind: .symbol(.lessThan)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.greaterThan)),
                makeToken(kind: .identifier(interner.intern("id"))),
                makeToken(kind: .symbol(.lParen)),
                makeToken(kind: .identifier(interner.intern("x"))),
                makeToken(kind: .symbol(.colon)),
                makeToken(kind: .identifier(interner.intern("T"))),
                makeToken(kind: .symbol(.rParen)),
                makeToken(kind: .symbol(.assign)),
                makeToken(kind: .identifier(interner.intern("x"))),
                makeToken(kind: .eof),
            ],
            interner: interner,
            diagnostics: diagnostics
        )
        let parsed = parserE.parseFile()
        let kinds = Set(parsed.arena.nodes.map(\.kind))
        #expect(kinds.contains(.typeArgs))
    }

    @Test
    func testParserCoversRareDeclarationEnumAndMissingNameBranches() {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        var offset = 0

        func token(_ kind: TokenKind, leadingNewline: Bool = false) -> Token {
            defer { offset += 1 }
            return Token(
                kind: kind,
                range: makeRange(file: FileID(rawValue: 0), start: offset, end: offset + 1),
                leadingTrivia: leadingNewline ? [.newline] : [],
                trailingTrivia: []
            )
        }

        let tokens: [Token] = [
            token(.keyword(.public)),
            token(.keyword(.package)),
            token(.identifier(interner.intern("pkg"))),
            token(.symbol(.semicolon)),

            token(.keyword(.private), leadingNewline: true),
            token(.keyword(.import)),
            token(.identifier(interner.intern("pkg"))),
            token(.symbol(.dot)),
            token(.symbol(.star)),
            token(.symbol(.semicolon)),

            token(.keyword(.companion), leadingNewline: true),
            token(.keyword(.class)),
            token(.identifier(interner.intern("CompanionHost"))),
            token(.symbol(.semicolon)),

            token(.keyword(.object), leadingNewline: true),
            token(.identifier(interner.intern("StandaloneObject"))),

            token(.keyword(.class), leadingNewline: true),
            token(.symbol(.lessThan)),
            token(.identifier(interner.intern("T"))),
            token(.symbol(.greaterThan)),
            token(.symbol(.lBrace)),
            token(.symbol(.rBrace)),

            token(.keyword(.val), leadingNewline: true),
            token(.symbol(.lBrace)),
            token(.symbol(.rBrace)),

            token(.keyword(.typealias), leadingNewline: true),
            token(.symbol(.assign)),
            token(.identifier(interner.intern("AliasTarget"))),

            token(.keyword(.fun), leadingNewline: true),
            token(.identifier(interner.intern("top"))),
            token(.symbol(.lParen)),
            token(.symbol(.rParen)),
            token(.symbol(.lBrace)),
            token(.symbol(.rBrace)),

            token(.keyword(.enum), leadingNewline: true),
            token(.identifier(interner.intern("NoBody"))),
            token(.symbol(.assign)),
            token(.intLiteral("1")),

            token(.keyword(.enum), leadingNewline: true),
            token(.keyword(.class)),
            token(.identifier(interner.intern("E"))),
            token(.symbol(.lBrace)),
            token(.identifier(interner.intern("A"))),
            token(.symbol(.lParen)),
            token(.intLiteral("1")),
            token(.symbol(.rParen)),
            token(.symbol(.comma)),
            token(.keyword(.fun)),
            token(.identifier(interner.intern("f"))),
            token(.symbol(.lParen)),
            token(.symbol(.rParen)),
            token(.symbol(.assign)),
            token(.intLiteral("1")),
            token(.symbol(.semicolon)),
            token(.intLiteral("2")),
            token(.symbol(.rBrace)),
            token(.eof),
        ]

        let parser = KotlinParser(tokens: tokens, interner: interner, diagnostics: diagnostics)
        let parsed = parser.parseFile()

        #expect(!(parsed.arena.nodes.isEmpty))
        let kinds = Set(parsed.arena.nodes.map(\.kind))
        #expect(kinds.contains(.packageHeader))
        #expect(kinds.contains(.importHeader))
        #expect(kinds.contains(.classDecl))
        #expect(kinds.contains(.objectDecl))
        #expect(kinds.contains(.propertyDecl))
        #expect(kinds.contains(.typeAliasDecl))
        #expect(kinds.contains(.funDecl))
        #expect(kinds.contains(.enumEntry))
        #expect(kinds.contains(.block))
        #expect(kinds.contains(.statement))

        let codes = Set(diagnostics.diagnostics.map(\.code))
        #expect(codes.contains("KSWIFTK-PARSE-0002"))
    }

    @Test
    func testParserWarnsForUnterminatedTypeArgsAndParameterGroup() {
        let interner = StringInterner()

        let typeArgDiagnostics = DiagnosticEngine()
        let typeArgTokens: [Token] = [
            makeToken(kind: .keyword(.fun)),
            makeToken(kind: .symbol(.lessThan)),
            makeToken(kind: .identifier(interner.intern("T"))),
            makeToken(kind: .identifier(interner.intern("broken"))),
            makeToken(kind: .symbol(.lParen)),
            makeToken(kind: .identifier(interner.intern("x"))),
            makeToken(kind: .symbol(.colon)),
            makeToken(kind: .identifier(interner.intern("T"))),
            makeToken(kind: .symbol(.rParen)),
            makeToken(kind: .symbol(.assign)),
            makeToken(kind: .identifier(interner.intern("x"))),
            makeToken(kind: .eof),
        ]
        let typeArgParser = KotlinParser(tokens: typeArgTokens, interner: interner, diagnostics: typeArgDiagnostics)
        let typeArgParsed = typeArgParser.parseFile()
        #expect(typeArgParsed.arena.nodes.contains { $0.kind == .typeArgs })
        #expect(typeArgDiagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0005" })

        let groupDiagnostics = DiagnosticEngine()
        let groupTokens: [Token] = [
            makeToken(kind: .keyword(.fun)),
            makeToken(kind: .identifier(interner.intern("broken"))),
            makeToken(kind: .symbol(.lParen)),
            makeToken(kind: .identifier(interner.intern("x"))),
            makeToken(kind: .symbol(.colon)),
            makeToken(kind: .identifier(interner.intern("Int"))),
            makeToken(kind: .eof),
        ]
        let groupParser = KotlinParser(tokens: groupTokens, interner: interner, diagnostics: groupDiagnostics)
        _ = groupParser.parseFile()
        #expect(groupDiagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" })
    }
}
#endif

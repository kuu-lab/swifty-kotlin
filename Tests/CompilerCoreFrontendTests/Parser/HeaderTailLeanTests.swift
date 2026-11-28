#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("import p", true, 2, false),
        ("import p;", true, 3, false),
        ("import p;;", true, 3, false),
        ("import p as alias;", true, 5, false),
        ("import p as `as`;", true, 5, false),
        ("import p\nas alias\n;", true, 5, false),
        ("import p as\nprivate;", true, 5, false),
        ("import p as", true, 3, true),
        ("import p as as;", true, 3, true),
        ("import p as .;", true, 3, true),
        ("import p as\nval next", true, 3, true),
        ("import p as ; ;", true, 4, true),
        ("import p as\n;", true, 4, true),
        ("package p as alias;", false, 2, false),
        ("package p;\n;", false, 3, false),
        ("package p", false, 2, false),
    ])
    func headerTailLeavesExpectedToken(source: String, isImport: Bool, consumed: Int, missingAlias: Bool) throws {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        let header = isImport ? parser.parseImportHeader() : parser.parsePackageHeader()
        let children = parser.arena.children(of: header).compactMap { child -> Token? in
            guard case let .token(id) = child else { return nil }
            return parser.arena.token(id)
        }

        #expect(parser.stream.index == consumed)
        #expect(parser.stream.peek() == lexed.tokens[consumed])
        if missingAlias {
            let asIndex = try #require(lexed.tokens.firstIndex { $0.kind == .keyword(.as) })
            let missingLocation = lexed.tokens[asIndex + 1].range.start
            let missingRange = SourceRange(start: missingLocation, end: missingLocation)
            var expectedChildren = Array(lexed.tokens.prefix(consumed))
            expectedChildren.insert(Token(kind: .missing(expected: .identifier(.invalid)), range: missingRange), at: asIndex + 1)
            #expect(children == expectedChildren)
            #expect(lexed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0005"])
            #expect(lexed.diagnostics.diagnostics.first?.primaryRange == missingRange)
        } else {
            #expect(children == Array(lexed.tokens.prefix(consumed)))
            #expect(lexed.diagnostics.diagnostics.isEmpty)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeRefParserTests {
    @Test(arguments: [
        "@C (() -> Unit)?",
        "@C (() -> Unit)",
        "@C ((() -> Unit))",
        "@C ((() -> Unit)?)",
        "@C ((Int) -> Int)",
        "@C ((Int) -> Int)?",
        "@C (((Int) -> Int)?)",
        "@C ((x: Int) -> Unit)",
        "@C ((@D Int) -> Unit)",
    ])
    func typeAnnotationBeforeParenthesizedTypeParses(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let result = try #require(TypeRefParserCore.parseTypeRefPrefix(
            lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            options: .declaration,
            diagnostics: lexed.diagnostics
        ))
        #expect(result.consumed == lexed.tokens.count - 1)
        #expect(!lexed.diagnostics.hasError)
        guard case let .annotated(base, annotations) = arena.typeRef(result.ref) else {
            Issue.record("Expected an annotated type for \(source)")
            return
        }
        #expect(annotations.count == 1)
        #expect(annotations.first?.name == "C")
        #expect(annotations.first?.arguments.isEmpty == true)
        guard case .functionType = arena.typeRef(base) else {
            Issue.record("Expected a function type base for \(source)")
            return
        }
    }

    @Test(arguments: [
        ("@T (\"a\") (() -> Unit)?", "\"a\""),
        ("@T (x = 1) ((Int) -> Int)", "x=1"),
    ])
    func typeAnnotationArgumentsBeforeParenthesizedTypeParse(_ source: String, expectedArgument: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let result = try #require(TypeRefParserCore.parseTypeRefPrefix(
            lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            options: .declaration,
            diagnostics: lexed.diagnostics
        ))
        #expect(result.consumed == lexed.tokens.count - 1)
        #expect(!lexed.diagnostics.hasError)
        guard case let .annotated(base, annotations) = arena.typeRef(result.ref) else {
            Issue.record("Expected an annotated type for \(source)")
            return
        }
        #expect(annotations.count == 1)
        #expect(annotations.first?.name == "T")
        let argument = try #require(annotations.first?.arguments.first)
        #expect(argument == expectedArgument)
        guard case .functionType = arena.typeRef(base) else {
            Issue.record("Expected a function type base for \(source)")
            return
        }
    }

    @Test
    func typeAnnotationArgumentListBeforeNamedTypeParses() throws {
        let lexed = lex("@T (\"a\") Int")
        let arena = ASTArena()
        let result = try #require(TypeRefParserCore.parseTypeRefPrefix(
            lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            options: .declaration,
            diagnostics: lexed.diagnostics
        ))
        #expect(result.consumed == lexed.tokens.count - 1)
        #expect(!lexed.diagnostics.hasError)
        guard case let .annotated(base, annotations) = arena.typeRef(result.ref) else {
            Issue.record("Expected an annotated type")
            return
        }
        #expect(annotations.count == 1)
        #expect(annotations.first?.name == "T")
        let argument = try #require(annotations.first?.arguments.first)
        #expect(argument == "\"a\"")
        guard case .named = arena.typeRef(base) else {
            Issue.record("Expected a named type base")
            return
        }
    }

    @Test(arguments: [
        "@C (Int)",
        "@C ((Int))",
        "@C (List<Int>)",
        "@C (List<() -> Unit>)",
    ])
    func typeAnnotationArgumentListWithoutFunctionTypeArrowIsNotAType(_ source: String) {
        let lexed = lex(source)
        let arena = ASTArena()
        let result = TypeRefParserCore.parseTypeRefPrefix(
            lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            options: .declaration,
            diagnostics: lexed.diagnostics
        )
        #expect(result == nil)
    }

    @Test(arguments: [
        "@C(() -> Unit)?",
        "@C(() -> Unit)",
    ])
    func typeAnnotationNoSpaceParenthesizedFunctionTypeIsRejected(_ source: String) {
        let lexed = lex(source)
        let arena = ASTArena()
        let result = TypeRefParserCore.parseTypeRefPrefix(
            lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            options: .declaration,
            diagnostics: lexed.diagnostics
        )
        #expect(result == nil)
    }

    @Test
    func annotatedParenthesizedTypesParseInDeclarationPositions() throws {
        let (_, ctx) = try buildASTModule(
            from: """
            annotation class C
            fun f(block: @C (() -> Unit)? = null): @C ((Int) -> Int)? = null
            class K {
                val p: @C ((Int) -> Int)? = null
                var q: List<@C (() -> Unit)?>? = null
            }
            typealias F = @C (() -> Unit)?
            """,
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-PARSE") })
    }
}
#endif

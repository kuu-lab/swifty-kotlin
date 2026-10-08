#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite("TypeRefParser")
struct TypeRefParserTests {
    @Test(arguments: [
        "T?.() -> Int", "T? .() -> Int", "T.() -> Int",
        "suspend T?.() -> Int", "suspend T? .() -> Int", "suspend T.() -> Int",
        "kotlin.collections.List<T>?.() -> Int",
        "suspend kotlin.collections.List<T>?.() -> Int",
        "(T?).() -> Int", "(T)?.() -> Int", "(T)? .() -> Int",
        "suspend (T?).() -> Int", "suspend (T)?.() -> Int",
    ])
    func receiverFunctionTypePreservesNullability(_ source: String) throws {
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
        try checkReceiverFunctionType(result.ref, in: arena, source: source)
    }

    @Test(arguments: [
        "T?.() -> Int", "T? .() -> Int", "T.() -> Int",
        "suspend T?.() -> Int", "suspend T? .() -> Int", "suspend T.() -> Int",
        "kotlin.collections.List<T>?.() -> Int", "(T?).() -> Int", "(T)?.() -> Int",
        "suspend (T?).() -> Int", "suspend (T)?.() -> Int",
    ])
    func explicitReceiverFunctionTypeArgumentIsNotAComparison(_ type: String) throws {
        for source in ["makeIt<\(type)>({ 1 })", "makeIt<\(type)> { 1 }"] {
            let lexed = lex(source)
            let arena = ASTArena()
            let parser = BuildASTPhase.ExpressionParser(
                tokens: lexed.tokens.dropLast(),
                interner: lexed.interner,
                astArena: arena,
                diagnostics: lexed.diagnostics
            )
            let expr = try #require(parser.parse())
            guard case let .call(callee, typeArgs, args, _) = arena.expr(expr) else {
                Issue.record("Expected an explicit generic call for \(source)")
                continue
            }
            guard case let .nameRef(name, _) = arena.expr(callee) else {
                Issue.record("Expected makeIt as the callee")
                continue
            }
            #expect(name == lexed.interner.intern("makeIt"))
            #expect(typeArgs.count == 1)
            #expect(args.count == 1)
            #expect(parser.current() == nil)
            #expect(!lexed.diagnostics.hasError)
            try checkReceiverFunctionType(try #require(typeArgs.first), in: arena, source: type)
        }
    }

    @Test(arguments: ["makeIt < value", "makeIt < value?.read()"])
    func failedTypeArgumentLookaheadPreservesComparison(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )
        let expr = try #require(parser.parse())
        guard case .binary(.lessThan, _, _, _) = arena.expr(expr) else {
            Issue.record("Expected a less-than comparison")
            return
        }
        #expect(parser.current() == nil)
        #expect(!lexed.diagnostics.hasError)
        if source.contains("?.") {
            #expect(arena.exprs.contains { if case .safeMemberCall = $0 { true } else { false } })
        }
    }

    @Test
    func classPropertyInitializerRetainsExplicitReceiverFunctionType() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun <X> makeIt(x: X): X = x
        class P<T : Any> {
            private val instance = makeIt<T?.() -> Int>({ 1 })
            fun read(value: T?): Int = instance(value)
        }
        """, includeStdlib: false)
        let property = try #require(memberProperty(named: "instance", ofClass: "P", in: ast, interner: ctx.interner))
        let initializer = try #require(property.initializer)
        guard case let .call(_, typeArgs, _, _) = ast.arena.expr(initializer) else {
            Issue.record("Expected a call initializer, not a comparison")
            return
        }
        #expect(!ctx.diagnostics.hasError)
        #expect(typeArgs.count == 1)
        try checkReceiverFunctionType(try #require(typeArgs.first), in: ast.arena, source: "T?.() -> Int")
    }

    private func checkReceiverFunctionType(_ ref: TypeRefID, in arena: ASTArena, source: String) throws {
        guard case let .functionType(_, receiver, params, returnType, isSuspend, nullable) = arena.typeRef(ref) else {
            Issue.record("Expected a receiver function type for \(source)")
            return
        }
        #expect(params.isEmpty)
        #expect(!nullable)
        #expect(isSuspend == source.hasPrefix("suspend "))
        guard case let .named(_, _, receiverNullable) = arena.typeRef(try #require(receiver)) else {
            Issue.record("Expected a named receiver")
            return
        }
        #expect(receiverNullable == source.contains("?"))
        guard case let .named(_, _, returnNullable) = arena.typeRef(returnType) else {
            Issue.record("Expected a named return type")
            return
        }
        #expect(!returnNullable)
    }

    @Test("Deeply nested function types report a diagnostic instead of recursing")
    func testDeeplyNestedFunctionTypeReportsDepthDiagnostic() {
        let interner = StringInterner()
        let arena = ASTArena()
        let diagnostics = DiagnosticEngine()

        let intName = interner.intern("Int")
        let depth = TypeRefParserCore.maxRecursionDepth + 1
        let tokens = makeFunctionTypeTokens(depth: depth, intName: intName)

        let result = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: arena,
            options: makeOptions(allowFunctionType: true),
            diagnostics: diagnostics
        )

        #expect(result == nil)
        #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-TYPE-DEPTH" })
    }

    @Test("Function types at the recursion limit still parse")
    func testFunctionTypeAtDepthLimitParses() {
        let interner = StringInterner()
        let arena = ASTArena()
        let diagnostics = DiagnosticEngine()

        let intName = interner.intern("Int")
        let depth = TypeRefParserCore.maxRecursionDepth
        let tokens = makeFunctionTypeTokens(depth: depth, intName: intName)

        let result = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: arena,
            options: makeOptions(allowFunctionType: true),
            diagnostics: diagnostics
        )

        #expect(result != nil)
        #expect(!diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-TYPE-DEPTH" })
    }

    @Test("Function type parameters with documentation labels still parse")
    func testLabeledFunctionTypeParametersParse() {
        let interner = StringInterner()
        let arena = ASTArena()
        let diagnostics = DiagnosticEngine()

        let accName = interner.intern("acc")
        let charName = interner.intern("Char")
        let valueKeyword = Keyword.value

        let tokens: [Token] = [
            makeToken(kind: .symbol(.lParen), start: 0, end: 1),
            makeToken(kind: .identifier(accName), start: 1, end: 4),
            makeToken(kind: .symbol(.colon), start: 4, end: 5),
            makeToken(kind: .identifier(charName), start: 5, end: 9),
            makeToken(kind: .symbol(.comma), start: 9, end: 10),
            makeToken(kind: .keyword(valueKeyword), start: 10, end: 15),
            makeToken(kind: .symbol(.colon), start: 15, end: 16),
            makeToken(kind: .identifier(charName), start: 16, end: 20),
            makeToken(kind: .symbol(.rParen), start: 20, end: 21),
            makeToken(kind: .symbol(.arrow), start: 21, end: 23),
            makeToken(kind: .identifier(charName), start: 23, end: 27),
        ]

        let result = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: arena,
            options: makeOptions(allowFunctionType: true, allowKeywordIdentifiers: true),
            diagnostics: diagnostics
        )

        #expect(result != nil)
        #expect(diagnostics.diagnostics.isEmpty)
        let typeRef = arena.typeRef(result!.ref)
        guard case .functionType(_, _, let params, _, _, _) = typeRef else {
            Issue.record("Parsed type was not a function type")
            return
        }
        #expect(params.count == 2)
    }

    @Test("Shallow nested generic types still parse successfully")
    func testShallowNestedGenericTypeParses() {
        let interner = StringInterner()
        let arena = ASTArena()
        let diagnostics = DiagnosticEngine()

        let listName = interner.intern("List")
        let intName = interner.intern("Int")

        let tokens: [Token] = [
            makeToken(kind: .identifier(listName), start: 0, end: 1),
            makeToken(kind: .symbol(.lessThan), start: 1, end: 2),
            makeToken(kind: .identifier(listName), start: 2, end: 3),
            makeToken(kind: .symbol(.lessThan), start: 3, end: 4),
            makeToken(kind: .identifier(intName), start: 4, end: 5),
            makeToken(kind: .symbol(.greaterThan), start: 5, end: 6),
            makeToken(kind: .symbol(.greaterThan), start: 6, end: 7),
        ]

        let result = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: arena,
            options: makeOptions(allowFunctionType: false),
            diagnostics: diagnostics
        )

        #expect(result != nil)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    private func makeOptions(
        allowFunctionType: Bool,
        allowKeywordIdentifiers: Bool = false
    ) -> TypeRefParserCore.Options {
        TypeRefParserCore.Options(
            allowQualifiedPath: true,
            allowFunctionType: allowFunctionType,
            allowKeywordIdentifiers: allowKeywordIdentifiers,
            reserveVarianceKeywords: false,
            allowTypeAnnotations: false
        )
    }

    private func makeFunctionTypeTokens(depth: Int, intName: InternedString) -> [Token] {
        var tokens: [Token] = []
        var offset = 0
        for _ in 0..<depth {
            tokens.append(makeToken(kind: .symbol(.lParen), start: offset, end: offset + 1))
            offset += 1
            tokens.append(makeToken(kind: .symbol(.rParen), start: offset, end: offset + 1))
            offset += 1
            tokens.append(makeToken(kind: .symbol(.arrow), start: offset, end: offset + 2))
            offset += 2
        }
        tokens.append(makeToken(kind: .identifier(intName), start: offset, end: offset + 1))
        return tokens
    }
}
#endif

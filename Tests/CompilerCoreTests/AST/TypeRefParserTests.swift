#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite("TypeRefParser")
struct TypeRefParserTests {

    @Test("Deeply nested function types report a diagnostic instead of recursing")
    func testDeeplyNestedFunctionTypeReportsDepthDiagnostic() {
        let interner = StringInterner()
        let arena = ASTArena()
        let diagnostics = DiagnosticEngine()

        let intName = interner.intern("Int")
        let depth = TypeRefParserCore.maxRecursionDepth + 1
        let tokens = makeFunctionTypeTokens(depth: depth, intName: intName)

        let options = TypeRefParserCore.Options(
            allowQualifiedPath: true,
            allowFunctionType: true,
            allowKeywordIdentifiers: false,
            reserveVarianceKeywords: false,
            allowTypeAnnotations: false
        )

        let result = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: arena,
            options: options,
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

        let options = TypeRefParserCore.Options(
            allowQualifiedPath: true,
            allowFunctionType: true,
            allowKeywordIdentifiers: false,
            reserveVarianceKeywords: false,
            allowTypeAnnotations: false
        )

        let result = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: arena,
            options: options,
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

        let options = TypeRefParserCore.Options(
            allowQualifiedPath: true,
            allowFunctionType: true,
            allowKeywordIdentifiers: true,
            reserveVarianceKeywords: false,
            allowTypeAnnotations: false
        )

        let result = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: arena,
            options: options,
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

        let options = TypeRefParserCore.Options(
            allowQualifiedPath: true,
            allowFunctionType: false,
            allowKeywordIdentifiers: false,
            reserveVarianceKeywords: false,
            allowTypeAnnotations: false
        )

        let result = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: arena,
            options: options,
            diagnostics: diagnostics
        )

        #expect(result != nil)
        #expect(diagnostics.diagnostics.isEmpty)
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

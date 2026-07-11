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
}
#endif
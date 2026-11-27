@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("value class Id", true), ("enum class Color", true),
        ("companion object", true), ("companion()", false),
    ])
    func genuineDeclarationBridgeMatchesSwift(source: String, expected: Bool) {
        let lexed = lex(source)
        let swift = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
        let lean = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())

        #expect(swift.startsGenuineDeclaration(at: 0) == expected)
        #expect((LeanParser.declarationPrefixVerdict(lean, at: 0) == .declaration) == expected)
        #expect(lean.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: [
        ("@A get() = field", false), ("private set", false),
        ("get", true), ("@ get() = field", false),
    ])
    func propertyAccessorBridgeMatchesSwift(source: String, allowsBodyless: Bool) {
        let lexed = lex(source)
        let swift = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
        let lean = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())

        let expected = swift.isPropertyAccessorStart(allowsBodyless: allowsBodyless)
        #expect(LeanParser.isPropertyAccessorStart(lean, allowsBodyless: allowsBodyless) == expected)
        #expect(lean.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: ["(T)", "(T\nprivate fun next() {}", "(T"])
    func balancedGroupBridgeMatchesSwiftRecoveryPosition(source: String) throws {
        let lexed = lex(source)
        let swift = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())
        let lean = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: DiagnosticEngine())

        _ = swift.parseBalancedGroup(opening: .lParen, closing: .rParen)
        let result = try #require(LeanParser.scanBalancedGroup(
            lean, opening: .lParen, closing: .rParen, allowsValueParameters: false, allowsWhenSubjectVariable: false
        ))
        #expect(result.consumed == swift.stream.index)
        #expect(result.unterminated == swift.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" })
        #expect(lean.diagnostics.diagnostics.isEmpty)
    }
}

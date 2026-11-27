#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("\n: Base", true, false, false, false), ("\nwhere T: Base", true, false, false, false),
        ("\n(value: T)", true, true, false, false), ("\n(value: T)", true, false, false, true),
        ("\nby impl", true, false, true, false), ("\nby impl", true, false, false, true),
        ("\nfun f()", false, false, false, true), ("\nimport p.F", false, false, false, false),
    ])
    func declarationHeaderNewlineKeepsOnlyAllowedContinuations(
        source: String, includeBlock: Bool, classColon: Bool, delegation: Bool, stops: Bool
    ) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        #expect(LeanParser.stopsDeclarationHeaderAtNewline(
            parser, includeBlock: includeBlock, allowsClassHeaderColon: classColon, allowsClassDelegation: delegation
        ) == stops)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif

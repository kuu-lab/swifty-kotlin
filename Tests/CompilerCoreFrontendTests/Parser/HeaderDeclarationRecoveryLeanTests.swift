#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("", true, 0, ["KSWIFTK-PARSE-0001", "KSWIFTK-PARSE-0003"], [0, 0]),
        ("p as alias;", true, 4, ["KSWIFTK-PARSE-0001"], [0]),
        ("as ;", true, 2, ["KSWIFTK-PARSE-0001", "KSWIFTK-PARSE-0003", "KSWIFTK-PARSE-0005"], [0, 0, 1]),
        (";", false, 1, ["KSWIFTK-PARSE-0001", "KSWIFTK-PARSE-0003"], [0, 0]),
        ("val x", true, 0, ["KSWIFTK-PARSE-0001", "KSWIFTK-PARSE-0003"], [0, 0]),
        ("import ; next", true, 2, ["KSWIFTK-PARSE-0003"], [1]),
        ("import as Alias", true, 3, ["KSWIFTK-PARSE-0003"], [1]),
        ("package\nimport p", false, 1, ["KSWIFTK-PARSE-0003"], [1]),
        ("import\npackage p", true, 1, ["KSWIFTK-PARSE-0003"], [1]),
        ("package", false, 1, ["KSWIFTK-PARSE-0003"], [1]),
    ])
    func headerDeclarationRecoversAtMissingToken(
        source: String, isImport: Bool, consumed: Int, codes: [String], diagnosticTokenIndices: [Int]
    ) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        _ = isImport ? parser.parseImportHeader() : parser.parsePackageHeader()

        #expect(parser.stream.index == consumed)
        #expect(parser.stream.peek() == lexed.tokens[consumed])
        #expect(lexed.diagnostics.diagnostics.map(\.code) == codes)
        #expect(lexed.diagnostics.diagnostics.map(\.primaryRange) == diagnosticTokenIndices.map {
            let at = lexed.tokens[$0].range.start
            return SourceRange(start: at, end: at)
        })
    }
}
#endif

#if canImport(Testing)
import Foundation
import GoldenHarnessSupport
import Testing

private enum GoldenHarnessStaticCases {
    static let lexer = GoldenHarness.loadCasesOrCrash(suiteName: "Lexer")
    static let parser = GoldenHarness.loadCasesOrCrash(suiteName: "Parser")
    static let sema = GoldenHarness.loadCasesOrCrash(suiteName: "Sema")
    static let diagnostics = GoldenHarness.loadCasesOrCrash(suiteName: "Diagnostics")
}

@Suite("Golden.Lexer")
struct GoldenLexerGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.lexer)
    func matchesGolden(caseFile: GoldenHarnessCase) throws {
        try runGoldenTest(suiteName: "Lexer", caseFile: caseFile)
    }
}

@Suite("Golden.Parser")
struct GoldenParserGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.parser)
    func matchesGolden(caseFile: GoldenHarnessCase) throws {
        try runGoldenTest(suiteName: "Parser", caseFile: caseFile)
    }
}

@Suite("Golden.Sema")
struct GoldenSemaGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.sema)
    func matchesGolden(caseFile: GoldenHarnessCase) throws {
        try runGoldenTest(suiteName: "Sema", caseFile: caseFile)
    }
}

@Suite("Golden.Diagnostics")
struct GoldenDiagnosticsGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.diagnostics)
    func matchesGolden(caseFile: GoldenHarnessCase) throws {
        try runGoldenTest(suiteName: "Diagnostics", caseFile: caseFile)
    }
}

private func runGoldenTest(suiteName: String, caseFile: GoldenHarnessCase) throws {
    let renderedActual = try GoldenHarness.renderInSubprocess(suiteName: suiteName, sourcePath: caseFile.sourcePath)
    if try GoldenHarness.persistIfUpdating(suiteName: suiteName, sourcePath: caseFile.sourcePath, actual: renderedActual) {
        return
    }
    let actual   = GoldenHarness.normalizedForComparison(suiteName: suiteName, output: renderedActual)
    let expected = GoldenHarness.normalizedForComparison(suiteName: suiteName, output: try GoldenHarness.loadExpectedGolden(sourcePath: caseFile.sourcePath))
    #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(caseFile.basename)"))
}
#endif

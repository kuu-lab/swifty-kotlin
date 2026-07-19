#if canImport(Testing)
import Foundation
import GoldenHarnessSupport
import Testing

struct GoldenHarnessCaseBatch: Sendable, CustomTestStringConvertible {
    let cases: [GoldenHarnessCase]

    var testDescription: String {
        guard let first = cases.first else {
            return "empty"
        }
        guard let last = cases.last, last.basename != first.basename else {
            return first.basename
        }
        return "\(first.basename)...\(last.basename) (\(cases.count) cases)"
    }
}

private enum GoldenHarnessStaticCases {
    private static let batchSize = 8

    static let lexer = batches(suiteName: "Lexer")
    static let parser = batches(suiteName: "Parser")
    static let sema = batches(suiteName: "Sema")
    static let diagnostics = batches(suiteName: "Diagnostics")

    private static func batches(suiteName: String) -> [GoldenHarnessCaseBatch] {
        let cases = GoldenHarness.loadCasesOrCrash(suiteName: suiteName)
        return stride(from: 0, to: cases.count, by: batchSize).map { startIndex in
            let endIndex = min(startIndex + batchSize, cases.count)
            return GoldenHarnessCaseBatch(cases: Array(cases[startIndex ..< endIndex]))
        }
    }
}

@Suite("Golden.Lexer")
struct GoldenLexerGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.lexer)
    func matchesGolden(batch: GoldenHarnessCaseBatch) throws {
        try runGoldenTests(suiteName: "Lexer", batch: batch)
    }
}

@Suite("Golden.Parser")
struct GoldenParserGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.parser)
    func matchesGolden(batch: GoldenHarnessCaseBatch) throws {
        try runGoldenTests(suiteName: "Parser", batch: batch)
    }
}

@Suite("Golden.Sema")
struct GoldenSemaGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.sema)
    func matchesGolden(batch: GoldenHarnessCaseBatch) throws {
        try runGoldenTests(suiteName: "Sema", batch: batch)
    }
}

@Suite("Golden.Diagnostics")
struct GoldenDiagnosticsGoldenTests {
    @Test(arguments: GoldenHarnessStaticCases.diagnostics)
    func matchesGolden(batch: GoldenHarnessCaseBatch) throws {
        try runGoldenTests(suiteName: "Diagnostics", batch: batch)
    }
}

private func runGoldenTests(suiteName: String, batch: GoldenHarnessCaseBatch) throws {
    let results = try GoldenHarness.renderBatchInSubprocess(
        suiteName: suiteName,
        sourcePaths: batch.cases.map(\.sourcePath)
    )

    for (caseFile, result) in zip(batch.cases, results) {
        if let errorDescription = result.errorDescription {
            Issue.record("Golden worker failed for \(caseFile.basename): \(errorDescription)")
            continue
        }
        guard let renderedActual = result.output else {
            Issue.record("Golden worker returned no output for \(caseFile.basename)")
            continue
        }

        do {
            try verifyGolden(suiteName: suiteName, caseFile: caseFile, renderedActual: renderedActual)
        } catch {
            Issue.record("Golden verification failed for \(caseFile.basename): \(error)")
        }
    }
}

private func verifyGolden(
    suiteName: String,
    caseFile: GoldenHarnessCase,
    renderedActual: String
) throws {
    if try GoldenHarness.persistIfUpdating(suiteName: suiteName, sourcePath: caseFile.sourcePath, actual: renderedActual) {
        return
    }
    let actual   = GoldenHarness.normalizedForComparison(suiteName: suiteName, output: renderedActual)
    let expected = GoldenHarness.normalizedForComparison(suiteName: suiteName, output: try GoldenHarness.loadExpectedGolden(sourcePath: caseFile.sourcePath))
    #expect(actual == expected, Comment(rawValue: "Golden mismatch: \(caseFile.basename)"))
}
#endif

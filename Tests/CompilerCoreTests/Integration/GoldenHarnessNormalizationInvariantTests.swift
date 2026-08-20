#if canImport(Testing)
import Foundation
import GoldenHarnessSupport
import Testing

/// Regression guard: every committed `.golden` file must already be a fixed
/// point of its suite's comparison normalizer (`GoldenHarness.normalizedForComparison`).
///
/// A file that is NOT a fixed point was committed through some path other
/// than `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden`
/// (for example a raw `GoldenHarnessWorker` invocation redirected straight to
/// disk). Such a file embeds process-local ordinals — synthetic local
/// namespace counters, expression occurrence indices — that were only
/// coincidentally small at generation time and drift the next time the file
/// is regenerated, even though nothing about the file itself changed.
@Suite("GoldenHarness.NormalizationInvariant")
struct GoldenHarnessNormalizationInvariantTests {
    @Test(arguments: ["Lexer", "Parser", "Sema", "Diagnostics"])
    func committedGoldensAreAlreadyNormalized(suiteName: String) throws {
        for caseFile in GoldenHarness.loadCasesOrCrash(suiteName: suiteName) {
            let goldenURL = URL(fileURLWithPath: caseFile.sourcePath)
                .deletingPathExtension()
                .appendingPathExtension("golden")
            guard let committed = try? String(contentsOf: goldenURL, encoding: .utf8) else {
                continue
            }
            let normalized = GoldenHarness.normalizedForComparison(suiteName: suiteName, output: committed)
            guard normalized != committed else {
                continue
            }
            Issue.record(Comment(rawValue: """
                \(caseFile.basename): committed .golden is not normalized (regenerate with \
                UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden \
                -Xswiftc -swift-version -Xswiftc 6)
                """))
        }
    }
}
#endif

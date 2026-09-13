#if canImport(Testing)
import Foundation
import GoldenHarnessSupport
import Testing

/// Regression guard: no two cases within one golden suite may carry the same
/// Kotlin source, so no two cases render the same dump.
///
/// A duplicate case costs a full frontend + Sema pass on every golden run and
/// on every `UPDATE_GOLDEN` regeneration while pinning nothing a sibling does
/// not already pin. Two landed without being noticed:
/// `stdlib_kotlin_ParameterName_n_n.kt` was a byte copy of
/// `stdlib_kotlin_n_ParameterName.kt` added by a ledger PR filling a naming
/// slot, and `charsets_object.kt` was a copy of `bytearray_decode_charset.kt`
/// whose own header comment promised a nine-constant surface its body never
/// exercised. Both were authored months apart by different PRs, so this is a
/// recurring event and not a one-off.
///
/// Deliberately compares **inputs**, not goldens. Goldens have an unbounded
/// false-positive class: every Diagnostics case that asserts "this construct
/// emits nothing" renders the same empty `diagnostics: []` document (7 do
/// today), and that set grows with every new negative fixture.
///
/// Deliberately compares **within** a suite, not across. The same input
/// intentionally appears in two suites to pin two different dumps — e.g.
/// `Parser/delegate_property.kt` and `Sema/delegate_property.kt`. Those pairs
/// carry different `package` headers, so they can never collide inside one
/// suite; restricting the check to a suite makes that soundness structural
/// rather than coincidental.
@Suite("GoldenHarness.DuplicateCaseInvariant")
struct GoldenHarnessDuplicateCaseInvariantTests {
    /// Lexer goldens dump the token stream, where a comment is itself an
    /// observable token, so that suite compares raw source. Every other suite
    /// renders post-parse structure that no comment can influence, so there a
    /// case differing from a sibling only in its comments really is a
    /// duplicate — and comparing comment-stripped text is what catches it.
    static func comparisonKey(suiteName: String, source: String) -> String {
        guard suiteName != "Lexer" else {
            return source
        }
        return source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test(arguments: ["Lexer", "Parser", "Sema", "Diagnostics"])
    func noTwoCasesInASuiteShareTheSameSource(suiteName: String) throws {
        var basenamesByKey: [String: [String]] = [:]
        for caseFile in GoldenHarness.loadCasesOrCrash(suiteName: suiteName) {
            let source = try String(
                contentsOf: URL(fileURLWithPath: caseFile.sourcePath),
                encoding: .utf8
            )
            let key = Self.comparisonKey(suiteName: suiteName, source: source)
            basenamesByKey[key, default: []].append(caseFile.basename)
        }

        let duplicateGroups = basenamesByKey.values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
        for group in duplicateGroups {
            Issue.record(Comment(rawValue: """
                \(suiteName): \(group.joined(separator: ", ")) carry the same Kotlin source \
                and therefore render the same dump. Keep one and delete the others, or give \
                each the distinct surface its name describes.
                """))
        }
    }
}
#endif

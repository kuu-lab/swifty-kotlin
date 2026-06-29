#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-COMP-FN-004: kotlin.comparisons.compareValuesBy (selector form).
///
/// Verifies that
/// `fun <T> compareValuesBy(a: T, b: T, selector: (T) -> Comparable<*>?): Int`
/// is registered as a synthetic stub in the kotlin.comparisons package and
/// resolves cleanly from user source code.
@Suite
struct ComparisonsCompareValuesByFunctionTests {

    /// Calling `compareValuesBy(a, b, selector)` from user source must resolve
    /// to the synthetic 1-selector stub without semantic errors.
    @Test func testCompareValuesByFunctionResolvesInSource() throws {
        let source = """
        import kotlin.comparisons.compareValuesBy

        fun cmp(): Int {
            val selector: (Int) -> Int = { x -> x }
            return compareValuesBy(13, 25, selector)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "compareValuesBy (1-selector) must resolve without errors; got: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// The 1-selector overload of `kotlin.comparisons.compareValuesBy`
    /// must be registered with the `kk_compareValuesBy1` external link.
    @Test func testCompareValuesByOneSelectorIsRegistered() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "comparisons", "compareValuesBy"].map { ctx.interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: fq)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(links.contains("kk_compareValuesBy1"), "compareValuesBy (1-selector) must link to kk_compareValuesBy1; found: \(links)")
        }
    }
}
#endif

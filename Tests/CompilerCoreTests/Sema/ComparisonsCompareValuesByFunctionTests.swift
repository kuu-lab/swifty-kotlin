#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-COMP-FN-004: kotlin.comparisons.compareValuesBy (selector form).
///
/// Verifies that
/// `fun <T> compareValuesBy(a: T, b: T, selector: (T) -> Comparable<*>?): Int`
/// KSP-461: it is provided by bundled Kotlin source (Stdlib/kotlin/comparisons/
/// Comparators.kt) and must resolve cleanly from user source code.
@Suite
struct ComparisonsCompareValuesByFunctionTests {

    /// Calling `compareValuesBy(a, b, selector)` from user source must resolve
    /// to the 1-selector overload without semantic errors.
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

    /// KSP-461: the 2-selector overload shares its arity with the
    /// `comparator + selector` one, so it must still resolve unambiguously.
    @Test func testCompareValuesByTwoSelectorsResolvesInSource() throws {
        let source = """
        fun cmp(): Int =
            compareValuesBy("ab", "cd", { s: String -> s.length }, { s: String -> s })
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "compareValuesBy (2-selector) must resolve without errors; got: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// KSP-461: the 1-selector overload is bundled Kotlin source, so it must be
    /// registered without any runtime external link.
    @Test func testCompareValuesByOneSelectorIsSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "comparisons", "compareValuesBy"].map { ctx.interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: fq)
            let isSourceBacked = symbols.contains { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == nil
                    && sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count == 3
            }
            #expect(isSourceBacked, "compareValuesBy (1-selector) must be bundled Kotlin source")
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            #expect(links.isEmpty, "compareValuesBy must not keep runtime links; found: \(links)")
        }
    }
}
#endif

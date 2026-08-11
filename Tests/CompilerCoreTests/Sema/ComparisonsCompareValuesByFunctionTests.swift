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

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import kotlin.comparisons.compareValuesBy

        fun cmp(): Int {
            val selector: (Int) -> Int = { x -> x }
            return compareValuesBy(13, 25, selector)
        }
        """,
        """
        package sample1
        fun cmp(): Int =
            compareValuesBy("ab", "cd", { s: String -> s.length }, { s: String -> s })
        """,
        """
        package sample2
        fun noop() {}
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    /// Calling `compareValuesBy(a, b, selector)` from user source must resolve
    /// to the 1-selector overload without semantic errors.
    @Test func testCompareValuesByFunctionResolvesInSource() throws {

        let ctx = try sharedCtx()
            #expect(!(ctx.diagnostics.hasError), "compareValuesBy (1-selector) must resolve without errors; got: \(ctx.diagnostics.diagnostics)")

    }

    /// KSP-461: the 2-selector overload shares its arity with the
    /// `comparator + selector` one, so it must still resolve unambiguously.
    @Test func testCompareValuesByTwoSelectorsResolvesInSource() throws {

        let ctx = try sharedCtx()
            #expect(!(ctx.diagnostics.hasError), "compareValuesBy (2-selector) must resolve without errors; got: \(ctx.diagnostics.diagnostics)")

    }

    /// KSP-461: the 1-selector overload is bundled Kotlin source, so it must be
    /// registered without any runtime external link.
    @Test func testCompareValuesByOneSelectorIsSourceBacked() throws {

        let ctx = try sharedCtx()
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
#endif

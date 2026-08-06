#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-COMP-FN-004: kotlin.comparisons.compareValuesBy (selector form).
///
/// Verifies that
/// `fun <T> compareValuesBy(a: T, b: T, selector: (T) -> Comparable<*>?): Int`
/// is registered from the bundled kotlin.comparisons source and resolves
/// cleanly from user source code.
@Suite
struct ComparisonsCompareValuesByFunctionTests {

    /// Calling `compareValuesBy(a, b, selector)` from user source must resolve
    /// to the source-backed 1-selector overload without semantic errors.
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

    /// KSP-461: the 1-selector overload of `kotlin.comparisons.compareValuesBy`
    /// comes from bundled Kotlin source and must not keep a kk_* runtime link.
    @Test func testCompareValuesByOneSelectorIsSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "comparisons", "compareValuesBy"].map { ctx.interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: fq)
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            #expect(links.isEmpty, "compareValuesBy must not keep runtime links; found: \(links)")
            #expect(
                symbols.contains { sema.symbols.functionSignature(for: $0)?.parameterTypes.count == 3 },
                "compareValuesBy(a, b, selector) must be registered from bundled stdlib source"
            )
        }
    }
}
#endif

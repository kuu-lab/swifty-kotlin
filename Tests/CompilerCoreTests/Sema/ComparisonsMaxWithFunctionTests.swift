#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-684: top-level kotlin.comparisons.maxWith/minWith (3-arg comparator forms).
///
/// Verifies that
/// `fun <T> maxWith(comparator: Comparator<in T>, a: T, b: T): T`
/// and its minWith sibling are registered from bundled Kotlin source and
/// resolve cleanly from user source code without an external runtime link.
@Suite
struct ComparisonsTopLevelMaxMinWithFunctionTests {
    @Test func testMaxWithAndMinWithFunctionsResolveFromBundledSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.maxWith
        import kotlin.comparisons.minWith
        import kotlin.comparisons.naturalOrder

        fun biggerOf(a: Int, b: Int): Int {
            return maxWith(naturalOrder<Int>(), a, b)
        }

        fun smallerOf(a: Int, b: Int): Int {
            return minWith(naturalOrder<Int>(), a, b)
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        for name in ["maxWith", "minWith"] {
            let fqName = ["kotlin", "comparisons", name].map { ctx.interner.intern($0) }
            let candidates = sema.symbols.lookupAll(fqName: fqName)
            #expect(candidates.count == 1, "Expected one bundled \(name) declaration, found \(candidates.count)")
            #expect(candidates.contains { sema.symbols.isSourceBackedSymbol($0) }, "\(name) must be source-backed")
            #expect(candidates.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil }, "\(name) must not use a runtime link")
        }
    }
}
#endif

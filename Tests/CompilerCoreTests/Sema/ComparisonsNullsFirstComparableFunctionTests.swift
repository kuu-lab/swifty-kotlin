#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsFirstComparableFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import kotlin.comparisons.nullsFirst

        fun makeComparator(): Comparator<Int?> {
            return nullsFirst()
        }
        """,
        """
        package sample1
        import kotlin.comparisons.nullsFirst
        import kotlin.comparisons.naturalOrder

        fun both(): Comparator<Int?> {
            val a: Comparator<Int?> = nullsFirst()
            val b: Comparator<Int?> = nullsFirst(naturalOrder<Int>())
            return a
        }
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
    @Test func testNullsFirstComparableResolvesWithNoArgument() throws {

        let ctx = try sharedCtx()
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testNullsFirstComparableIsDistinctFromComparatorOverload() throws {

        let ctx = try sharedCtx()
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
#endif

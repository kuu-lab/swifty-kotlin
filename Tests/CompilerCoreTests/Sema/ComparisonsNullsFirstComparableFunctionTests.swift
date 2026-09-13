#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ComparisonsNullsFirstComparableFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testNullsFirstComparableResolvesWithNoArgument
            """
            package sample0

                    import kotlin.comparisons.nullsFirst

                    fun makeComparator(): Comparator<Int?> {
                        return nullsFirst()
                    }

            """,
            // testNullsFirstComparableIsDistinctFromComparatorOverload
            """
            package sample1

                    import kotlin.comparisons.nullsFirst
                    import kotlin.comparisons.naturalOrder

                    fun both(): Comparator<Int?> {
                        val a: Comparator<Int?> = nullsFirst()
                        val b: Comparator<Int?> = nullsFirst(naturalOrder<Int>())
                        return a
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            _ = try #require(ctx.sema)


            // === testNullsFirstComparableResolvesWithNoArgument ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(!sample0Diagnostics.contains { $0.severity == .error }, "resolve: \(sample0Diagnostics)")

            }

            // === testNullsFirstComparableIsDistinctFromComparatorOverload ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(!sample1Diagnostics.contains { $0.severity == .error }, "resolve: \(sample1Diagnostics)")

            }

        }
    }

}

#endif

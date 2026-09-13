@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-012: Validates that the source-defined `Sequence<T>.chunked`
/// overloads resolve through Sema for both size-only and transform forms.
@Suite
struct SequenceChunkedFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testSequenceChunkedSizeOnlyOverloadResolvesFromBundledSource
            """
            package sample0

                    fun probe(values: Sequence<Int>): Sequence<List<Int>> {
                        return values.chunked(3)
                    }

            """,
            // testSequenceChunkedSizeTransformOverloadResolvesFromBundledSource
            """
            package sample1

                    fun probe(values: Sequence<Int>): Sequence<Int> {
                        return values.chunked(3) { chunk -> chunk.size }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            _ = try #require(ctx.sema)


            // === testSequenceChunkedSizeOnlyOverloadResolvesFromBundledSource ===

            do {

                let sample0Path = paths[0]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Expected Sequence.chunked(size) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
                )

            }

            // === testSequenceChunkedSizeTransformOverloadResolvesFromBundledSource ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Expected Sequence.chunked(size, transform) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
                )

            }

        }
    }

}

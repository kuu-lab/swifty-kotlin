@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-012: Validates that the source-defined `Sequence<T>.chunked`
/// overloads resolve through Sema for both size-only and transform forms.
@Suite
struct SequenceChunkedFunctionTests {
    @Test func testSequenceChunkedSizeOnlyOverloadResolvesFromBundledSource() throws {
        let source = """
        fun probe(values: Sequence<Int>): Sequence<List<Int>> {
            return values.chunked(3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected Sequence.chunked(size) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )

        }
    }

    @Test func testSequenceChunkedSizeTransformOverloadResolvesFromBundledSource() throws {
        let source = """
        fun probe(values: Sequence<Int>): Sequence<Int> {
            return values.chunked(3) { chunk -> chunk.size }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected Sequence.chunked(size, transform) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )

        }
    }
}

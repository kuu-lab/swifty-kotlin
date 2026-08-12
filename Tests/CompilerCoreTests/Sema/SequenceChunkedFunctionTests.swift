@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-012: Validates that the source-defined `Sequence<T>.chunked`
/// overloads resolve through Sema for both size-only and transform forms.
@Suite
struct SequenceChunkedFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun probe(values: Sequence<Int>): Sequence<List<Int>> {
            return values.chunked(3)
        }
        """,
        """
        package sample1
        fun probe(values: Sequence<Int>): Sequence<Int> {
            return values.chunked(3) { chunk -> chunk.size }
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
    @Test func testSequenceChunkedSizeOnlyOverloadResolvesFromBundledSource() throws {

        let ctx = try sharedCtx()
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected Sequence.chunked(size) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )


    }

    @Test func testSequenceChunkedSizeTransformOverloadResolvesFromBundledSource() throws {

        let ctx = try sharedCtx()
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected Sequence.chunked(size, transform) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )


    }
}

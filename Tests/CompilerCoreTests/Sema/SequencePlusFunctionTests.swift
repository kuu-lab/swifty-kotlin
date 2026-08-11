@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-087: `kotlin.sequences.Sequence<T>.plus` の Sema 解決を検証する。
@Suite
struct SequencePlusFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun probe(values: Sequence<Int>) {
            val combined: Sequence<Int> = values.plus(sequenceOf(3, 4))
            println(combined)
        }
        """,
        """
        package sample1
        fun probe(values: Sequence<Int>): Sequence<Int> {
            return values + sequenceOf(3, 4)
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
    @Test func testSequencePlusMemberCallResolvesToRuntimeABI() throws {

        let ctx = try sharedCtx()
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Sequence.plus member call to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try #require(ctx.sema)
            let memberFQName = [
                "kotlin", "sequences", "Sequence", "plus",
            ].map(ctx.interner.intern)
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                links.contains("kk_sequence_plus"),
                "Expected Sequence.plus to link to kk_sequence_plus, got: \(links)"
            )

    }

    @Test func testSequencePlusOperatorResolvesToRuntimeABI() throws {

        let ctx = try sharedCtx()
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Sequence + Sequence operator to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try #require(ctx.sema)
            let memberFQName = [
                "kotlin", "sequences", "Sequence", "plus",
            ].map(ctx.interner.intern)
            let links = Set(
                sema.symbols.lookupAll(fqName: memberFQName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            #expect(
                links.contains("kk_sequence_plus"),
                "Expected Sequence + Sequence operator to resolve to kk_sequence_plus, got: \(links)"
            )

    }
}

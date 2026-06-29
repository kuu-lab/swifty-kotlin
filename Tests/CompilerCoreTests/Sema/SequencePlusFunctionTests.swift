@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-087: `kotlin.sequences.Sequence<T>.plus` の Sema 解決を検証する。
@Suite
struct SequencePlusFunctionTests {
    @Test func testSequencePlusMemberCallResolvesToRuntimeABI() throws {
        let source = """
        fun probe(values: Sequence<Int>) {
            val combined: Sequence<Int> = values.plus(sequenceOf(3, 4))
            println(combined)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

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
    }

    @Test func testSequencePlusOperatorResolvesToRuntimeABI() throws {
        let source = """
        fun probe(values: Sequence<Int>): Sequence<Int> {
            return values + sequenceOf(3, 4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

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
}

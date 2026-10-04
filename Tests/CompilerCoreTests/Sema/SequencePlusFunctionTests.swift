@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-SEQ-FN-087: `kotlin.sequences.Sequence<T>.plus` の Sema 解決を検証する。
@Suite
struct SequencePlusFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testSequencePlusMemberCallResolvesToRuntimeABI
            """
            package sample0

                    fun probe(values: Sequence<Int>) {
                        val combined: Sequence<Int> = values.plus(sequenceOf(3, 4))
                        println(combined)
                    }

            """,
            // testSequencePlusOperatorResolvesToRuntimeABI
            """
            package sample1

                    fun probe(values: Sequence<Int>): Sequence<Int> {
                        return values + sequenceOf(3, 4)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testSequencePlusMemberCallResolvesToRuntimeABI ===

            do {

                let sample0Path = paths[0]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Sequence.plus member call to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

                let memberFQName = [
                    "kotlin", "sequences", "Sequence", "plus",
                ].map(interner.intern)
                let links = Set(
                    sema.symbols.lookupAll(fqName: memberFQName)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(
                    links.contains("kk_sequence_plus"),
                    "Expected Sequence.plus to link to kk_sequence_plus, got: \(links)"
                )

            }

            // === testSequencePlusOperatorResolvesToRuntimeABI ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Sequence + Sequence operator to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

                let memberFQName = [
                    "kotlin", "sequences", "Sequence", "plus",
                ].map(interner.intern)
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

}

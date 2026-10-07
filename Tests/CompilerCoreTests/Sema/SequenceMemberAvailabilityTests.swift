@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SequenceMemberAvailabilityTests {
    @Test
    func unavailableMembersAndZipArgumentsAreRejected() throws {
        let expressions = [
            "sequenceOf(1, 2, 3).takeLast(2).toList()",
            "sequenceOf(1, 2, 3).takeLastWhile { it > 1 }.toList()",
            "sequenceOf(1, 2, 3).reversed().toList()",
            "sequenceOf(1, 2, 3).zip(listOf(\"a\", \"b\")).toList()",
            "sequenceOf(1, 2, 3).zip(arrayOf(\"a\", \"b\")).toList()",
            "s.takeLast(2)",
            "s.takeLastWhile { it > 1 }",
            "s.reversed()",
            "s.zip(other)",
            "s.zip(arrayOf(\"a\", \"b\")) { a, b -> b }",
            "s.zip(other) { a, b -> b }",
            "s.zip(nullable)",
            "s?.reversed()",
            // KUU-1413: kotlin.sequences has no reduceRight family — kotlinc
            // rejects all four as unresolved references on a Sequence.
            "sequenceOf(1, 2, 3).reduceRight { a, b -> a - b }",
            "sequenceOf(1, 2, 3).reduceRightOrNull { a, b -> a - b }",
            "sequenceOf(1, 2, 3).reduceRightIndexed { i, a, b -> a - b - i }",
            "sequenceOf(1, 2, 3).reduceRightIndexedOrNull { i, a, b -> a - b - i }",
            "s.reduceRight { a, b -> a - b }",
            "s.reduceRightOrNull { a, b -> a - b }",
            "s.reduceRightIndexed { i, a, b -> a - b - i }",
            "s.reduceRightIndexedOrNull { i, a, b -> a - b - i }",
        ]
        let sources = expressions.enumerated().map { index, expression in
            """
            package rejected\(index)
            fun probe(s: Sequence<Int>, other: Iterable<String>, nullable: Sequence<String>?) {
                \(expression)
            }
            """
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for (index, path) in paths.enumerated() {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(!errors.isEmpty, "Expected rejection of \(expressions[index])")
                #expect(
                    errors.contains { $0.code == "KSWIFTK-SEMA-0024" || $0.code == "KSWIFTK-SEMA-0003"
                        || $0.code == "KSWIFTK-TYPE-0001" },
                    "Expected member/overload diagnostic for \(expressions[index]), got \(errors)"
                )
            }
        }
    }

    @Test
    func validSequenceAndEagerCollectionOperationsRemainAvailable() throws {
        let source = """
        fun probe(s: Sequence<Int>, other: Sequence<String>, list: List<Int>) {
            val pairs: Sequence<Pair<Int, String>> = s.zip(other)
            val transformed: Sequence<String> = s.zip(other) { a, b -> b }
            val chained = sequenceOf(1, 2, 3).zip(sequenceOf("a", "b")).toList()
            val shuffled: Sequence<Int> = s.shuffled()
            val descending: Sequence<Int> = s.sortedDescending()
            val tail: List<Int> = list.takeLast(2)
            val suffix: List<Int> = list.takeLastWhile { it > 1 }
            val reverse: List<Int> = list.reversed()
            val eagerTail = s.toList().takeLast(2)
            val eagerSuffix = s.toList().takeLastWhile { it > 1 }
            val eagerReverse = s.toList().reversed()
            // KUU-1413: the one-pass reduce family stays available on Sequence;
            // only the right-fold variants were removed.
            val reduced: Int = s.reduce { acc, v -> acc + v }
            val reducedOrNull: Int? = s.reduceOrNull { acc, v -> acc + v }
            val reducedIndexed: Int = s.reduceIndexed { i, acc, v -> acc + v + i }
            val reducedIndexedOrNull: Int? = s.reduceIndexedOrNull { i, acc, v -> acc + v + i }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected valid calls: \(errors)")
        }
    }

    @Test
    func userDefinedSequenceExtensionsRemainAvailable() throws {
        let source = """
        fun Sequence<Int>.takeLast(n: Int): List<Int> = listOf(n)
        fun Sequence<Int>.takeLastWhile(predicate: (Int) -> Boolean): List<Int> = listOf(1)
        fun Sequence<Int>.reversed(): Sequence<Int> = this
        fun Sequence<Int>.zip(other: Iterable<String>): Int = 7
        fun probe(s: Sequence<Int>) {
            val tail: List<Int> = s.takeLast(2)
            val suffix: List<Int> = s.takeLastWhile { it > 1 }
            val reverse: Sequence<Int> = s.reversed()
            val zipped: Int = s.zip(listOf("a"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected user extensions: \(errors)")
        }
    }
}

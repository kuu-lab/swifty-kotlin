#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendKotlinTextAggregationEdgeCasesTests {

    @Test func testKotlinTextToMutableListEdgeCases() throws {
        let source = """
        fun main() {
            // empty string -> empty mutable list
            println("".toMutableList())

            // single char
            println("a".toMutableList())

            // multiple chars
            println("abc".toMutableList())

            // result is mutable: add grows the list, removeAt shrinks it
            val chars = "abc".toMutableList()
            chars.add('d')
            println(chars.size)
            chars.removeAt(3)
            println(chars)
            chars.removeAt(0)
            println(chars)
            println(chars.size)

            // each call returns an independent copy
            val a = "xy".toMutableList()
            val b = "xy".toMutableList()
            a.add('z')
            println(a.size)
            println(b.size)
            println(b)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextToMutableListEdgeCases",
            expected:
                """
                []
                [a]
                [a, b, c]
                4
                [a, b, c]
                [b, c]
                2
                3
                2
                [x, y]
                """
                + "\n"
        )
    }

    @Test func testKotlinTextFirstNotNullOfEdgeCases() throws {
        let source = """
        fun firstFromSequence(value: CharSequence): String {
            return value.firstNotNullOf<String> { ch -> if (ch == 'b') "bee" else null }
        }

        fun main() {
            println(firstFromSequence("abc"))
            println("kotlin".firstNotNullOf<String> { ch -> if (ch == 't') "tea" else null })
            try {
                println("abc".firstNotNullOf<String> { ch -> null })
            } catch (e: Throwable) {
                println("missing")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextFirstNotNullOfEdgeCases",
            expected:
                """
                bee
                tea
                missing
                """
                + "\n"
        )
    }

    @Test func testKotlinTextFirstNotNullOfOrNullEdgeCases() throws {
        let source = """
        fun firstFromSequence(value: CharSequence): String? {
            return value.firstNotNullOfOrNull<String> { ch -> if (ch == 'b') "bee" else null }
        }

        fun main() {
            println(firstFromSequence("abc"))
            println("kotlin".firstNotNullOfOrNull<String> { ch -> if (ch == 't') "tea" else null })
            println("abc".firstNotNullOfOrNull<String> { ch -> null } ?: "missing")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextFirstNotNullOfOrNullEdgeCases",
            expected:
                """
                bee
                tea
                missing
                """
                + "\n"
        )
    }

    @Test func testKotlinTextReduceRightIndexedEdgeCases() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char {
            return value.reduceRightIndexed { index, ch, acc -> if (index == 1) ch else acc }
        }

        fun main() {
            println(reduceFromSequence("abc"))
            println("abcd".reduceRightIndexed { index, ch, acc -> if (index == 0) ch else acc })
            try {
                println("".reduceRightIndexed { index, ch, acc -> if (index == 0) ch else acc })
            } catch (e: Throwable) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReduceRightIndexedEdgeCases",
            expected:
                """
                b
                a
                empty
                """
                + "\n"
        )
    }

    @Test func testKotlinTextReduceRightIndexedOrNullEdgeCases() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char? {
            return value.reduceRightIndexedOrNull { index, ch, acc -> if (index == 1) ch else acc }
        }

        fun main() {
            println(reduceFromSequence("abc") ?: 'x')
            println("abcd".reduceRightIndexedOrNull { index, ch, acc -> if (index == 0) ch else acc } ?: 'x')
            println("".reduceRightIndexedOrNull { index, ch, acc -> if (index == 0) ch else acc } ?: 'x')
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReduceRightIndexedOrNullEdgeCases",
            expected:
                """
                b
                a
                x
                """
                + "\n"
        )
    }

    @Test func testKotlinTextReduceRightOrNullEdgeCases() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char? {
            return value.reduceRightOrNull { ch, acc -> if (ch == 'b') ch else acc }
        }

        fun main() {
            println(reduceFromSequence("abc") ?: 'x')
            println("abcd".reduceRightOrNull { ch, acc -> if (ch == 'a') ch else acc } ?: 'x')
            println("".reduceRightOrNull { ch, acc -> if (ch == 'a') ch else acc } ?: 'x')
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextReduceRightOrNullEdgeCases",
            expected:
                """
                b
                a
                x
                """
                + "\n"
        )
    }

    @Test func testKotlinTextReduceOrNullEdgeCases() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char? {
            return value.reduceOrNull { acc, ch -> if (ch == 'b') ch else acc }
        }

        fun main() {
            println(reduceFromSequence("abc") ?: 'x')
            println("abcd".reduceOrNull { acc, ch -> if (acc == 'a') acc else ch } ?: 'x')
            println("".reduceOrNull { acc, ch -> acc } ?: 'x')
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KotlinTextReduceOrNullEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            let expected =
                """
                b
                a
                x
                """
                + "\n"
            #expect(out == expected)
        }
    }

    @Test func testKotlinTextSumByEdgeCases() throws {
        let source = """
        fun sumFromSequence(value: CharSequence): Int {
            return value.sumBy { if (it == 'a') 10 else 1 }
        }

        fun main() {
            println(sumFromSequence("aba"))
            println("bbb".sumBy { ch -> if (ch == 'b') 3 else 0 })
            println("".sumBy { 1 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSumByEdgeCases",
            expected:
                """
                21
                9
                0
                """
                + "\n"
        )
    }

    @Test func testKotlinTextSumByDoubleEdgeCases() throws {
        let source = """
        fun sumFromSequence(value: CharSequence): Double {
            return value.sumByDouble { if (it == 'a') 1.5 else 0.25 }
        }

        fun main() {
            println(sumFromSequence("aba"))
            println("bbb".sumByDouble { ch -> if (ch == 'b') 2.0 else 0.0 })
            println("".sumByDouble { 1.0 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextSumByDoubleEdgeCases",
            expected:
                """
                3.25
                6.0
                0.0
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-FN-094: CharSequence.toCollection(destination)
    @Test func testKotlinTextToCollectionEdgeCases() throws {
        let source = """
        fun main() {
            val list = mutableListOf<Char>('x')
            val returnedList: MutableList<Char> = "ab".toCollection(list)
            println(returnedList)
            println(list)
            println(returnedList.size)

            val cs: CharSequence = "cda"
            val set = mutableSetOf<Char>('c')
            val returnedSet: MutableSet<Char> = cs.toCollection(set)
            println(returnedSet)
            println(returnedSet.size)

            val empty = mutableListOf<Char>('q')
            println("".toCollection(empty))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextToCollectionEdgeCases",
            expected:
                """
                [x, a, b]
                [x, a, b]
                3
                [c, d, a]
                3
                [q]
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-FN-108: CharSequence.toSortedSet(): SortedSet<Char>
    // End-to-end execution coverage — the runtime/Sema layers are tested in
    // isolation elsewhere; this asserts the full compile-and-run pipeline
    // produces a sorted, deduplicated set that honours the `Set` surface.
    @Test func testKotlinTextToSortedSetEdgeCases() throws {
        let source = """
        fun main() {
            // Basic: sorted ascending and deduplicated ('l' appears twice).
            val h = "hello".toSortedSet()
            println(h)
            println(h.size)

            // Reverse-ordered input is sorted into ascending order.
            println("cba".toSortedSet())

            // The result honours the Set surface (membership queries).
            println(h.contains('l'))
            println(h.contains('z'))

            // Ordering follows the natural Char (UTF-16 code unit) order, so
            // digits precede letters.
            println("b3a1".toSortedSet())

            // CharSequence receiver resolves to the same extension.
            val cs: CharSequence = "banana"
            val b: Set<Char> = cs.toSortedSet()
            println(b)
            println(b.size)

            // Empty input yields an empty set.
            val e = "".toSortedSet()
            println(e)
            println(e.size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KotlinTextToSortedSetEdgeCases",
            expected:
                """
                [e, h, l, o]
                4
                [a, b, c]
                true
                false
                [1, 3, a, b]
                [a, b, n]
                3
                []
                0
                """
                + "\n"
        )
    }
}
#endif

@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesArrayEdgeCases() throws {
        let source = """
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            val empty = emptyArray<Int>()
            println(empty.size)

            val single = arrayOf(7)
            println(single[0])

            val many = arrayOf(1, 2, 3)
            println(many[0])
            println(many[1])
            println(many[2])

            val ints = intArrayOf(4, 5, 6)
            println(ints[1])

            val stringArray = arrayOf("a", "c", "e", "g")
            println(stringArray.binarySearch("c"))
            println(stringArray.binarySearch("d", 1))
            println(stringArray.binarySearch("g", 1, 4))

            println(ints.binarySearch(5))
            println(ints.binarySearch(7, 1))
            println(ints.binarySearch(6, 1, 3))

            val uintArray = uintArrayOf(10u, 20u, 30u, 40u)
            println(uintArray.binarySearch(30u))
            println(uintArray.binarySearch(15u, 1))
            println(uintArray.binarySearch(40u, 1, 4))

            val ulongArray = ulongArrayOf(10uL, 20uL, 30uL, 40uL)
            println(ulongArray.binarySearch(30uL))
            println(ulongArray.binarySearch(15uL, 1))
            println(ulongArray.binarySearch(40uL, 1, 4))

            val boxed: Array<Any> = arrayOf<Any>(1, "two", 3)
            println(boxed[1])

            try {
                println(many[10])
            } catch (e: Throwable) {
                println("oob-get")
            }

            try {
                many[10] = 99
                println("unexpected-set")
            } catch (e: Throwable) {
                println("oob-set")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayEdgeCases",
            expected:
                """
                0
                7
                1
                2
                3
                5
                1
                -3
                3
                1
                -4
                2
                2
                -2
                3
                2
                -2
                3
                two
                oob-get
                oob-set
                """
                + "\n"
        )
    }

    func testCodegenCompilesArrayBinarySearchWithComparator() throws {
        let source = """
        fun main() {
            val values = arrayOf(1, 3, 4, 9)
            val comparator = naturalOrder<Int>()
            println(values.binarySearch(4, comparator, 0, 4))
            println(values.binarySearch(5, comparator, 1, 3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayBinarySearchComparator",
            expected:
                """
                2
                -4
                """ + "\n"
        )
    }

    func testCodegenCompilesArraySortedArrayWith() throws {
        let source = """
        fun main() {
            val numbers = arrayOf(3, 1, 2)
            println(numbers.sortedArrayWith(naturalOrder()).toList())
            println(numbers.sortedArrayWith(reverseOrder()).toList())
            println(numbers.sortedArrayWith { a, b -> b - a }.toList())

            val words = arrayOf("bbb", "a", "cc")
            println(words.sortedArrayWith(compareBy<String> { it.length }).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArraySortedArrayWith",
            expected:
                """
                [1, 2, 3]
                [3, 2, 1]
                [3, 2, 1]
                [a, cc, bbb]
                """ + "\n"
        )
    }

    func testCodegenCompilesArrayOfNulls() throws {
        let source = """
        fun main() {
            val values: Array<String?> = arrayOfNulls<String>(3)
            val first: String? = values[0]
            println(values.size)
            println(first == null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayOfNulls",
            expected:
                """
                3
                true
                """ + "\n"
        )
    }

    func testCodegenArrayFirstNotNullOfOrNullReturnsFirstMatchOrNull() throws {
        let source = """
        fun main() {
            val result: String? = arrayOf(1, 2, 3).firstNotNullOfOrNull { if (it > 1) "hit" else null }
            println(result)
            val missing: String? = arrayOf(1, 3, 5).firstNotNullOfOrNull { if (it % 2 == 0) "even" else null }
            println(missing)
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFirstNotNullOfOrNull", expected: "hit\nnull\n")
    }

    func testArrayOfBoxesPrimitiveElementsForFilterIsInstance() throws {
        let source = """
        fun main() {
            val values: Array<Any> = arrayOf(1, "two", 3)
            println(values.asSequence().filterIsInstance<Int>().toList())
            println(values.asSequence().filterIsInstance<String>().toList())

            val mixed: Array<Any> = arrayOf(1.5, "x", 2.5, 7L, true)
            println(mixed.asSequence().filterIsInstance<Double>().toList())
            println(mixed.asSequence().filterIsInstance<Long>().toList())
            println(mixed.asSequence().filterIsInstance<Boolean>().toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayOfBoxesPrimitives",
            expected:
                """
                [1, 3]
                [two]
                [1.5, 2.5]
                [7]
                [true]
                """ + "\n"
        )
    }

}

/// Keep this regression in its own XCTestCase so SwiftPM does not have to
/// type-check the already-large CodegenBackendIntegrationTests discovery list.
final class ArrayForLoopIntegrationTests: XCTestCase {
    func testCodegenArrayForLoopIteratesAllElements() throws {
        let source = """
        fun main() {
            for (b in "HI".encodeToByteArray()) println(b.toInt())
            for (i in intArrayOf(10, 20, 30)) println(i)
            for (s in arrayOf("a", "b", "c")) println(s)
            for (c in charArrayOf('x', 'y', 'z')) println(c)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "ArrayForLoopIteration",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            XCTAssertEqual(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n"),
                "72\n73\n10\n20\n30\na\nb\nc\nx\ny\nz\n"
            )
        }
    }
}

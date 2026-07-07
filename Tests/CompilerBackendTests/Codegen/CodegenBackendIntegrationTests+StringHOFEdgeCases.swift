@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    // TEST-TEXT-018: filter / filterNot / filterIndexed
    func testCodegenStringFilterVariants() throws {
        let source = """
        fun main() {
            println("hello".filter { it == 'l' })
            println("hello".filter { it == 'z' })
            println("aaa".filter { it == 'a' })
            println("".filter { it == 'a' })
            println("hello".filterNot { it == 'l' })
            println("".filterNot { it == 'a' })
            println("abcde".filterIndexed { i, c -> i % 2 == 0 })
            println("".filterIndexed { i, c -> true })
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringHOFFilter",
            expected:
                """
                ll

                aaa

                heo

                ace

                """
                + "\n"
        )
    }

    // TEST-TEXT-018: map / mapIndexed / mapNotNull
    func testCodegenStringMapVariants() throws {
        let source = """
        fun main() {
            println("abc".map { it })
            println("".map { it })
            println("abc".mapIndexed { i, c -> i })
            println("abc".mapNotNull { if (it != 'b') it else null })
            println("xyz".mapNotNull { if (it == 'a') it else null })
            println("".mapNotNull { it })
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringHOFMap",
            expected:
                """
                [a, b, c]
                []
                [0, 1, 2]
                [a, c]
                []
                []
                """
                + "\n"
        )
    }

    // TEST-TEXT-018: all / any / none / count
    func testCodegenStringPredicateAggregates() throws {
        let source = """
        fun main() {
            println("abc".all { it != 'z' })
            println("abc".all { it == 'a' })
            println("".all { it == 'a' })
            println("abc".any { it == 'b' })
            println("abc".any { it == 'z' })
            println("".any { it == 'a' })
            println("abc".none { it == '0' })
            println("abc".none { it == 'b' })
            println("".none { it == 'a' })
            println("hello".count { it == 'l' })
            println("hello".count { it == 'z' })
            println("".count { it == 'a' })
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringHOFAggregates",
            expected:
                """
                true
                false
                true
                true
                false
                false
                true
                false
                true
                2
                0
                0
                """
                + "\n"
        )
    }

    // TEST-TEXT-018: find / findLast
    func testCodegenStringFindFindLast() throws {
        let source = """
        fun main() {
            println("hello".find { it == 'l' })
            println("hello".find { it == 'z' })
            println("".find { it == 'a' })
            println("hello".findLast { it == 'l' })
            println("hello".findLast { it == 'z' })
            println("".findLast { it == 'a' })
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringHOFFindFindLast",
            expected:
                """
                l
                null
                null
                l
                null
                null
                """
                + "\n"
        )
    }

    // TEST-TEXT-018: first / last / single — happy path (non-empty strings)
    func testCodegenStringFirstLastSingle() throws {
        let source = """
        fun main() {
            println("abc".first())
            println("abc".last())
            println("a".single())
            println("abc".first { it > 'a' })
            println("abc".last { it < 'c' })
            println("abc".single { it == 'b' })
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringHOFFirstLastSingle",
            expected:
                """
                a
                c
                a
                b
                b
                b
                """
                + "\n"
        )
    }

    // TEST-TEXT-018: firstOrNull / lastOrNull / singleOrNull — null on empty and multi-element
    func testCodegenStringNullableAccessors() throws {
        let source = """
        fun main() {
            println("abc".firstOrNull())
            println("".firstOrNull())
            println("abc".lastOrNull())
            println("".lastOrNull())
            println("a".singleOrNull())
            println("".singleOrNull())
            println("ab".singleOrNull())
            println("abc".singleOrNull())
            println("abc".firstOrNull { it == 'b' })
            println("abc".firstOrNull { it == 'z' })
            println("abc".lastOrNull { it < 'c' })
            println("abc".lastOrNull { it == 'z' })
            println("abc".singleOrNull { it == 'b' })
            println("abc".singleOrNull { it > 'a' })
            println("abc".getOrNull(1))
            println("abc".getOrNull(-1))
            println("abc".getOrNull(3))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringHOFNullable",
            expected:
                """
                a
                null
                c
                null
                a
                null
                null
                null
                b
                null
                b
                null
                b
                null
                null
                """
                + "\n"
        )
    }

    // TEST-TEXT-018: partition — verifies Pair<String,String> return via .first / .second
    func testCodegenStringPartition() throws {
        let source = """
        fun main() {
            val p1 = "hello".partition { it == 'l' }
            println(p1.first)
            println(p1.second)
            val p2 = "".partition { it == 'a' }
            println(p2.first)
            println(p2.second)
            val p3 = "aaa".partition { it == 'a' }
            println(p3.first)
            println(p3.second)
            val p4 = "bbb".partition { it == 'a' }
            println(p4.first)
            println(p4.second)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringHOFPartition",
            expected:
                """
                ll
                heo


                aaa


                bbb
                """
                + "\n"
        )
    }

    // TEST-TEXT-046: CharSequence.reduce
    func testCodegenStringReduce() throws {
        let source = """
        fun main() {
            println("abc".reduce { acc, c -> if (acc == 'b') acc else c })
            println("x".reduce { acc, c -> acc })
            println("abc".reduce { acc, c -> acc })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringHOFReduce",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                b
                x
                a
                """
                + "\n"
            )
        }
    }

    // TEST-TEXT-018: takeWhile / dropWhile
    func testCodegenStringTakeWhileDropWhile() throws {
        let source = """
        fun main() {
            println("abcde".takeWhile { it != 'c' })
            println("".takeWhile { it != 'c' })
            println("abcde".takeWhile { it != 'z' })
            println("".dropWhile { it == 'a' })
            println("aaabbc".dropWhile { it == 'a' })
            println("abcde".dropWhile { it == 'z' })
            println("aaaaa".dropWhile { it == 'a' })
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringHOFTakeDropWhile",
            expected:
                """
                ab

                abcde

                bbc
                abcde

                """
                + "\n"
        )
    }
}

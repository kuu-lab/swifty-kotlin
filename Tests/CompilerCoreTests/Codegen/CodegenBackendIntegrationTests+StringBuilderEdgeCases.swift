@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesStringBuilderAppendRangeEdgeCases() throws {
        let source = """
        fun main() {
            println(StringBuilder("hello").appendRange("WORLD", 1, 4).toString())

            val sb = StringBuilder("01")
            sb.appendRange("abcd", 0, 2)
            println(sb.toString())

            val implicit = with(StringBuilder("rust")) {
                appendRange("SWIFT", 1, 4)
                toString()
            }
            println(implicit)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderAppendRangeEdgeCases",
            expected:
                """
                helloORL
                01ab
                rustWIF
                """
                + "\n"
        )
    }

    func testCodegenCompilesStringBuilderDeleteAtEdgeCases() throws {
        let source = """
        fun main() {
            println(StringBuilder("abc").deleteAt(1).toString())

            val sb = StringBuilder("xy")
            sb.deleteAt(0)
            println(sb.toString())

            val implicit = with(StringBuilder("rust")) {
                deleteAt(1)
                toString()
            }
            println(implicit)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderDeleteAtEdgeCases",
            expected:
                """
                ac
                y
                rst
                """
                + "\n"
        )
    }

    func testCodegenCompilesStringBuilderDeleteRangeEdgeCases() throws {
        let source = """
        fun main() {
            println(StringBuilder("abcdef").deleteRange(1, 4).toString())

            val sb = StringBuilder("012345")
            sb.deleteRange(2, 5)
            println(sb.toString())

            val implicit = with(StringBuilder("abcdef")) {
                deleteRange(0, 2)
                toString()
            }
            println(implicit)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderDeleteRangeEdgeCases",
            expected:
                """
                aef
                015
                cdef
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-FN-024: insert
    func testCodegenCompilesStringBuilderInsertEdgeCases() throws {
        let source = """
        fun main() {
            println(StringBuilder("ac").insert(1, "b").toString())

            val sb = StringBuilder("bd")
            sb.insert(0, "a")
            sb.insert(2, "c")
            println(sb.toString())

            val implicit = with(StringBuilder("xz")) {
                insert(1, "y")
                toString()
            }
            println(implicit)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderInsertEdgeCases",
            expected:
                """
                abc
                abcd
                xyz
                """
                + "\n"
        )
    }

    func testCodegenCompilesStringBuilderInsertRangeEdgeCases() throws {
        let source = """
        fun main() {
            println(StringBuilder("ab").insertRange(1, "WXYZ", 1, 3).toString())

            val sb = StringBuilder("01")
            sb.insertRange(2, "abcd", 0, 2)
            println(sb.toString())

            val implicit = with(StringBuilder("rust")) {
                insertRange(0, "SWIFT", 1, 4)
                toString()
            }
            println(implicit)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderInsertRangeEdgeCases",
            expected:
                """
                aXYb
                01ab
                WIFrust
                """
                + "\n"
        )
    }

    func testCodegenCompilesStringBuilderSetRangeEdgeCases() throws {
        let source = """
        fun main() {
            println(StringBuilder("abcd").setRange(1, 3, "XYZ").toString())

            val sb = StringBuilder("012345")
            sb.setRange(2, 5, "AB")
            println(sb.toString())

            val implicit = with(StringBuilder("rust")) {
                setRange(0, 2, "SW")
                toString()
            }
            println(implicit)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderSetRangeEdgeCases",
            expected:
                """
                aXYZd
                01AB5
                SWst
                """
                + "\n"
        )
    }

    // STDLIB-TEXT-FN-003: Typed append overloads for StringBuilder
    func testCodegenCompilesStringBuilderTypedAppendOverloads() throws {
        let source = """
        fun main() {
            val sb = StringBuilder()
            sb.append("hello")
            sb.append(' ')
            sb.append(true)
            sb.append(' ')
            sb.append(42)
            sb.append(' ')
            sb.append(100L)
            println(sb.toString())

            val sb2 = StringBuilder()
            sb2.append(3.14)
            println(sb2.toString())

            val sb3 = StringBuilder()
            val nullStr: String? = null
            sb3.append(nullStr)
            println(sb3.toString())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderTypedAppendOverloads",
            expected:
                """
                hello true 42 100
                3.14
                null
                """
                + "\n"
        )
    }

    func testCodegenCompilesAppendableAppendOverloads() throws {
        let source = """
        import kotlin.text.Appendable

        fun main() {
            val sb = StringBuilder()
            val target: Appendable = sb
            target.append('a')
            target.append("bc")
            target.append("def", 1, 3)
            println(sb.toString())
        }
        """

        try assertKotlinOutput(source, moduleName: "AppendableAppendOverloads", expected: "abcef\n")
    }

    // DEBT-RT-001: StringBuilder bounds checks throw catchable IndexOutOfBoundsException.
    func testCodegenStringBuilderInsertOutOfBoundsThrowsIndexOutOfBoundsException() throws {
        let source = """
        fun main() {
            try {
                StringBuilder("hello").insert(99, "x")
                println("no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "StringBuilderInsertOOB", expected: "caught\n")
    }
}


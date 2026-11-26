#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendStringBuilderEdgeCasesTests {

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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

            // KUU-641: insertRange must accept any CharSequence, not only String.
            val dst = StringBuilder("abc")
            val src = StringBuilder("XYZ")
            dst.insertRange(1, src, 0, 2)
            println(dst.toString())
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
                aXYbc
                """
                + "\n"
        )
    }

    @Test
    func testCodegenStringBuilderReversePreservesSurrogatePairs() throws {
        let source = """
        fun main() {
            val paired = StringBuilder("a\\uD800\\uDC00b")
            paired.reverse()
            println(paired[0] == 'b')
            println(paired[1] == '\\uD800')
            println(paired[2] == '\\uDC00')
            println(paired[3] == 'a')

            val unpaired = StringBuilder("\\uDC00\\uD800")
            unpaired.reverse()
            println(unpaired[0] == '\\uD800')
            println(unpaired[1] == '\\uDC00')

            println(StringBuilder("abc").reverse().toString())
            println(StringBuilder("x").reverse().toString())
            println(StringBuilder("").reverse().toString().length)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderReverseSurrogatePairs",
            expected:
                """
                true
                true
                true
                true
                true
                true
                cba
                x
                0
                """
                + "\n"
        )
    }

    @Test
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

    @Test
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

    @Test
    func testCodegenStringBuilderInsertOutOfBoundsThrowsIndexOutOfBoundsException() throws {
        let source = """
        fun main() {
            try {
                StringBuilder("hello").insert(99, "x")
                println("insert: no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("insert: caught")
            }

            try {
                StringBuilder("hello").insert(99, 'x')
                println("insertChar: no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("insertChar: caught")
            }

            try {
                StringBuilder("hello").insert(99, true)
                println("insertBoolean: no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("insertBoolean: caught")
            }

            try {
                StringBuilder("hello").insert(99, 3.14f)
                println("insertFloat: no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("insertFloat: caught")
            }

            try {
                StringBuilder("hello").insert(99, 2.718)
                println("insertDouble: no exception")
            } catch (e: IndexOutOfBoundsException) {
                println("insertDouble: caught")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderInsertOOB",
            expected:
                """
                insert: caught
                insertChar: caught
                insertBoolean: caught
                insertFloat: caught
                insertDouble: caught
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCompilesStringBuilderCapacityConstructor() throws {
        let source = """
        fun main() {
            val sb = StringBuilder(16)
            sb.append("hello")
            println(sb.toString())

            println(StringBuilder(8).append("world").toString())

            val implicit = with(StringBuilder(4)) {
                append("cap")
                toString()
            }
            println(implicit)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderCapacityConstructor",
            expected:
                """
                hello
                world
                cap
                """
                + "\n"
        )
    }

    @Test
    func testCodegenStringBuilderCapacityReservation() throws {
        try assertKotlinOutput(
            """
            fun main() {
                println(StringBuilder(100).capacity())
                val sb = StringBuilder()
                sb.ensureCapacity(200)
                println(sb.capacity())
                sb.append("a😀b")
                sb.ensureCapacity(1)
                println(sb.capacity())
                println(sb.toString())
                sb.trimToSize()
                println(sb.capacity())
                sb.clear()
                println(sb.capacity())
                sb.trimToSize()
                println(sb.capacity())
            }
            """,
            moduleName: "StringBuilderCapacityReservation",
            expected: "100\n200\n200\na😀b\n4\n4\n0\n"
        )
    }

    @Test
    func testCodegenStringBuilderIsCharSequenceAndAppendable() throws {
        let source = """
        fun main() {
            val sb = StringBuilder("hello")
            println(sb is CharSequence)
            println(sb is Appendable)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringBuilderIsCharSequenceAndAppendable",
            expected:
                """
                true
                true
                """
                + "\n"
        )
    }

    @Test
    func testCodegenBuildStringBuilderResultIsCharSequenceAndAppendable() throws {
        let source = """
        fun main() {
            val sb = buildStringBuilder { append("hello") }
            println(sb is CharSequence)
            println(sb is Appendable)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BuildStringBuilderResultIsCharSequenceAndAppendable",
            expected:
                """
                true
                true
                """
                + "\n"
        )
    }

    // so the regression cannot return. `replace`/`insertRange` are omitted here
    // because they currently fail overload resolution on an *implicit* receiver
    // (even inside a plain `with(StringBuilder()) { ... }`); that is a separate
    // pre-existing Sema issue unrelated to the BUG-043 runtime `this` handle.
    @Test
    func testCodegenBuildStringReceiverMethodsUseValidThisHandle() throws {
        let source = """
        fun main() {
            println(buildString { append("x"); reverse() })
            println(buildString { append("abc"); reverse() })
            println(buildString { append("abc"); clear(); append("z") })
            println(buildString { append("abc"); deleteAt(1) })
            println(buildString { append("abc"); deleteCharAt(0) })
            println(buildString { append("abc"); setCharAt(1, 'Y') })
            println(buildString { append("abc"); set(2, 'Z') })
            println(buildString { append("abc"); append(get(1)) })
            println(buildString { append("ab"); append(capacity() > 0) })
            println(buildString { append("ab"); ensureCapacity(64); trimToSize(); append("c") })
            println(buildString { append("abcd"); setRange(1, 3, "XY") })
            println(buildString { append("abcd"); deleteRange(1, 3) })
            println(buildString { append("hello"); append(toString().length) })
            println(buildStringBuilder { append("hi"); reverse() }.toString())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BuildStringReceiverMethodsUseValidThisHandle",
            expected:
                """
                x
                cba
                z
                ac
                bc
                aYc
                abZ
                abcb
                abtrue
                abc
                aXYd
                ad
                hello5
                ih
                """
                + "\n"
        )
    }
}
#endif

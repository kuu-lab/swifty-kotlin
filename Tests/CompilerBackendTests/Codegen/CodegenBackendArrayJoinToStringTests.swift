#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendArrayJoinToStringTests {

    @Test func testCodegenArrayJoinToStringUsesDefaultSeparator() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString())
            println(arr.joinToString { (it * 10).toString() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringDefault", expected: "1, 2, 3\n10, 20, 30\n")
    }

    @Test func testCodegenArrayJoinToStringWithCustomSeparator() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString(" | "))
            println(arr.joinToString(",") { (it * 10).toString() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringSeparator", expected: "1 | 2 | 3\n10,20,30\n")
    }

    @Test func testCodegenArrayJoinToStringWithPrefixAndPostfix() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString(separator = ":", prefix = "[", postfix = "]"))
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringPrefixPostfix", expected: "[1:2:3]\n")
    }

    @Test func testCodegenArrayJoinToStringOnEmptyArray() throws {
        let source = """
        fun main() {
            val empty = emptyArray<Int>()
            println(empty.joinToString())
            println(empty.joinToString(prefix = "<", postfix = ">"))
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringEmpty", expected: "\n<>\n")
    }

    @Test func testCodegenListAndArrayJoinToStringLimitTransformNullAndJoinTo() throws {
        let source = """
        fun main() {
            val list: List<Int?> = listOf(1, null, 3)
            val array: Array<Int?> = arrayOf(1, null, 3)

            println(list.joinToString("|", "<", ">", 2, "..."))
            println(list.joinToString("|", "<", ">", 2, "...") { it.toString() })
            val listBuffer = StringBuilder("list:")
            list.joinTo(listBuffer, "|", "<", ">", 2, "...")
            println(listBuffer.toString())

            println(array.joinToString("|", "<", ">", 2, "..."))
            println(array.joinToString("|", "<", ">", 2, "...") { it.toString() })
            val arrayBuffer = StringBuilder("array:")
            array.joinTo(arrayBuffer, "|", "<", ">", 2, "...")
            println(arrayBuffer.toString())

            println(emptyList<Int>().joinToString("|", "<", ">", 2, "..."))
            println(emptyArray<Int>().joinToString("|", "<", ">", 2, "..."))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListArrayJoinToStringEdgeCases",
            expected: "<1|null|...>\n<1|null|...>\nlist:<1|null|...>\n<1|null|...>\n<1|null|...>\narray:<1|null|...>\n<>\n<>\n"
        )
    }
}
#endif

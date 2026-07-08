@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenArrayJoinToStringUsesDefaultSeparator() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString())
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringDefault", expected: "1, 2, 3\n")
    }

    func testCodegenArrayJoinToStringWithCustomSeparator() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString(" | "))
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringSeparator", expected: "1 | 2 | 3\n")
    }

    func testCodegenArrayJoinToStringWithPrefixAndPostfix() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString(separator = ":", prefix = "[", postfix = "]"))
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringPrefixPostfix", expected: "[1:2:3]\n")
    }

    func testCodegenArrayJoinToStringOnEmptyArray() throws {
        let source = """
        fun main() {
            val empty = emptyArray<Int>()
            println(empty.joinToString())
            println(empty.joinToString(prefix = "<", postfix = ">"))
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringEmpty", expected: "\n<>\n")
    }

    // Regression test: `Array.joinToString(separator) { transform }` used to silently drop
    // the transform lambda (same root cause as the List/Iterable variant).
    func testCodegenArrayJoinToStringWithTransformLambda() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString(",") { (it * 10).toString() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringTransformSeparator", expected: "10,20,30\n")
    }

    func testCodegenArrayJoinToStringWithBareTransformLambda() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString { (it * 10).toString() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayJoinToStringTransformBare", expected: "10, 20, 30\n")
    }
}


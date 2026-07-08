@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenIterableJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.joinToString())
            println(collection.joinToString(" | "))
            println(collection.joinToString(prefix = "<", postfix = ">"))
            println(collection.joinToString(separator = ":", prefix = "[", postfix = "]"))

            val set: Set<String> = setOf("x", "y")
            println(set.joinToString(";"))
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableJoinToStringRuntime", expected: "1, 2, 3\n1 | 2 | 3\n<1, 2, 3>\n[1:2:3]\nx;y\n")
    }

    // Regression test for the bug where `joinToString(separator) { transform }` silently
    // dropped the transform lambda and joined the elements' raw `toString()` instead,
    // because `List`/`Iterable`'s synthetic `joinToString` member had no overload
    // accepting a trailing transform closure at all.
    func testCodegenListJoinToStringWithTransformLambda() throws {
        let source = """
        fun main() {
            val parts = "a\\r\\nbb\\r\\nccc".split("\\r\\n")
            println(parts.joinToString(",") { it.length.toString() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListJoinToStringTransformSeparator", expected: "1,2,3\n")
    }

    func testCodegenListJoinToStringWithBareTransformLambda() throws {
        let source = """
        fun main() {
            val list = listOf("a", "bb", "ccc")
            println(list.joinToString { it.length.toString() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListJoinToStringTransformBare", expected: "1, 2, 3\n")
    }

    func testCodegenListJoinToStringWithSeparatorPrefixPostfixAndTransformLambda() throws {
        let source = """
        fun main() {
            val list = listOf("a", "bb", "ccc")
            println(list.joinToString(",", "[", "]") { it.length.toString() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListJoinToStringTransformFull", expected: "[1,2,3]\n")
    }

    func testCodegenListJoinToStringTransformOnEmptyList() throws {
        let source = """
        fun main() {
            val empty = emptyList<String>()
            println(empty.joinToString { it.length.toString() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListJoinToStringTransformEmpty", expected: "\n")
    }

    func testCodegenIterableJoinToStringWithTransformLambda() throws {
        let source = """
        fun main() {
            val iter: Iterable<String> = listOf("a", "bb", "ccc")
            println(iter.joinToString("-") { "<" + it + ">" })
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableJoinToStringTransform", expected: "<a>-<bb>-<ccc>\n")
    }

    // Named-argument calls without a transform must keep resolving to the plain
    // (separator, prefix, postfix) overload, not to one of the newly-added
    // transform overloads that happen to share the same argument count.
    func testCodegenListJoinToStringNamedArgumentsWithoutTransformStillWork() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            println(list.joinToString(prefix = "<", postfix = ">"))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListJoinToStringNamedArgsNoTransformRegression", expected: "<1, 2, 3>\n")
    }

    func testCodegenListJoinToStringTransformPropagatesException() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            try {
                println(list.joinToString(",") {
                    if (it == 2) throw IllegalStateException("boom")
                    it.toString()
                })
                println("missing-throw")
            } catch (e: IllegalStateException) {
                println("caught: " + e.message)
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListJoinToStringTransformException", expected: "caught: boom\n")
    }
}


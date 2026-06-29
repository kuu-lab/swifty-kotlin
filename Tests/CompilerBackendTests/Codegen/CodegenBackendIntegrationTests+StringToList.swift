// STDLIB-TEXT-FN-101: End-to-end execution tests for CharSequence.toList().
// kk_string_toList materialises each Unicode scalar as a boxed Char and returns
// a List<Char>, so println renders it with the standard list format [a, b, c].
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testCodegenStringToList() throws {
        let source = """
        fun main() {
            // String literal receiver
            println("hello".toList())

            // empty string yields an empty list
            println("".toList())

            // CharSequence receiver resolves to the same conversion
            val cs: CharSequence = "abc"
            println(cs.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToList",
            expected:
                """
                [h, e, l, l, o]
                []
                [a, b, c]
                """
                + "\n"
        )
    }

    func testCodegenStringToListSupportsListOperations() throws {
        // The result is a genuine List<Char>, so size/first/last behave as expected.
        // (Indexing via chars[0] is intentionally avoided here: the get-operator
        // lowering mis-dispatches List<Char>[i] to kk_string_get — a pre-existing
        // bug unrelated to toList, reproducible with listOf('h','i')[0].)
        let source = """
        fun main() {
            val chars = "hi".toList()
            println(chars.size)
            println(chars.first())
            println(chars.last())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToListOps",
            expected:
                """
                2
                h
                i
                """
                + "\n"
        )
    }
}


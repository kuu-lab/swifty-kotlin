@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenStringReplaceFirstRemoveRange() throws {
        let source = """
        fun main() {
            // replaceFirst — only the first occurrence is replaced
            println("hello world hello".replaceFirst("hello", "hi"))
            println("hello world".replaceFirst("xyz", "abc"))

            // removeRange(startIndex, endIndex) — exclusive end
            println("hello world".removeRange(5, 11))
            println("hello world".removeRange(0, 6))
            println("hello".removeRange(2, 2))

            // removeRange(range) — IntRange, end is inclusive
            println("hello world".removeRange(5..10))
            println("hello world".removeRange(0..5))

            // replaceRange(range, replacement) — replaces chars in the given inclusive range
            println("hello world".replaceRange(0..4, "bye"))
            println("hello world".replaceRange(6..10, "Kotlin"))

            // replaceRange(startIndex, endIndex, replacement) — exclusive end (STDLIB-TEXT-FN-062)
            println("hello world".replaceRange(0, 5, "bye"))
            println("hello world".replaceRange(6, 11, "Kotlin"))
            println("hello".replaceRange(1, 4, "EL"))
            println("hello".replaceRange(0, 0, "HH"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringReplaceFirstRemoveRange",
            expected:
                """
                hi world hello
                hello world
                hello
                world
                hello
                hello
                world
                bye world
                hello Kotlin
                bye world
                hello Kotlin
                hELo
                HHhello
                """
                + "\n"
        )
    }

    func testCodegenReplaceFirstIgnoreCase() throws {
        let source = """
        fun main() {
            println("abcABC".replaceFirst("abc", "X", ignoreCase = true))
            println("HELLO world HELLO".replaceFirst("hello", "hi", ignoreCase = true))
            println("hello".replaceFirst("xyz", "Z", ignoreCase = true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ReplaceFirstIgnoreCase",
            expected:
                """
                XABC
                hi world HELLO
                hello
                """
                + "\n"
        )
    }
}

@testable import CompilerCore
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
                """
                + "\n"
        )
    }
}


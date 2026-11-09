#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendStringRegexAndFormattingTests {

    // TEST-TEXT-020: String and Regex pure Kotlin operations
    @Test
    func testCodegenStringPureKotlinRegexAndFormattingOperations() throws {
        let source = """
        fun main() {
            val r1 = "a.c".toRegex()
            println("abc".matches(r1))
            println("axc".matches(r1))
            println("123".matches(r1))
            println("xyz abc 123".contains(r1))
            println("xyz".contains(r1))

            val r2 = "hello".toRegex(RegexOption.IGNORE_CASE)
            println("HELLO".matches(r2))

            val r3 = "^test$".toRegex(setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE))
            println("TEST".matches(r3))

            println("hello".concat(" world"))
            println("".concat("kotlin"))

            println("Hello %s %d".format("world", 42))

            val cs: CharSequence = "hello"
            println(cs.codePointCount())
            println(cs.codePointCount(2))
            println(cs.codePointCount(1, 4))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "StringPureKotlinRegexAndFormatting",
            expected:
                """
                true
                true
                false
                true
                false
                true
                true
                hello world
                kotlin
                Hello world 42
                5
                3
                3
                """
                + "\n"
        )
    }
}
#endif

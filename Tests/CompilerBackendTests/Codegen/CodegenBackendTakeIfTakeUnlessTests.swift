#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendTakeIfTakeUnlessTests {

    // STDLIB-TEXT-FN-079: String.takeIf / String.takeUnless
    @Test
    func testCodegenStringTakeIfTakeUnless() throws {
        let source = """
        fun main() {
            // takeIf: returns receiver String if predicate is true, else null
            println("hello".takeIf { it.isNotEmpty() })   // hello
            println("".takeIf { it.isNotEmpty() })        // null
            println("kotlin".takeIf { it.length > 3 })   // kotlin
            println("hi".takeIf { it.length > 5 })       // null

            // takeUnless: returns receiver String if predicate is false, else null
            println("hello".takeUnless { it.isEmpty() })  // hello
            println("".takeUnless { it.isEmpty() })       // null
            println("kotlin".takeUnless { it.length > 10 })  // kotlin
            println("hello world".takeUnless { it.length > 5 })  // null
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringTakeIfTakeUnless",
            expected: "hello\nnull\nkotlin\nnull\nhello\nnull\nkotlin\nnull\n"
        )
    }
}
#endif

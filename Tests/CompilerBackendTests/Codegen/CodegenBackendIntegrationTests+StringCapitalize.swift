@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite struct CodegenBackendStringCapitalizeTests {

    @Test func testCodegenStringCapitalizeUppercasesFirstChar() throws {
        let source = """
        fun main() {
            println("hello".capitalize())
            println("world".capitalize())
            println("abc def".capitalize())
        }
        """

        try assertKotlinOutput(source, moduleName: "StringCapitalize", expected: "Hello\nWorld\nAbc def\n")
    }

    @Test func testCodegenStringCapitalizeHandlesEdgeCases() throws {
        let source = """
        fun main() {
            println("".capitalize())
            println("Hello".capitalize())
            println("A".capitalize())
        }
        """

        try assertKotlinOutput(source, moduleName: "StringCapitalizeEdgeCases", expected: "\nHello\nA\n")
    }
}
#endif

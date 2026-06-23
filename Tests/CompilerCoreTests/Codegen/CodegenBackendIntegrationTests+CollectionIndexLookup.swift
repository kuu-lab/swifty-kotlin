import XCTest
@testable import CompilerCore

extension CodegenBackendIntegrationTests {
    func testCodegenListIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 10)
            println(values.indexOf(10))
            println(values.indexOf(20))
            println(values.indexOf(30))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListIndexOfRuntime", expected: "0\n1\n-1\n")
    }

    func testCodegenListOfCharIndexOperatorUsesListGet() throws {
        let source = """
        fun main() {
            val chars = listOf('h', 'i')
            println(chars[0])
            println(chars[1])
            // A List<Char> obtained via String.toList() must behave the same.
            println("hi".toList()[0])
            // The member forms already worked and must keep working alongside the operator.
            println(chars.get(0))
            println(chars.first())
            println(chars.last())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListOfCharIndexOperator", expected: "h\ni\nh\nh\nh\ni\n")
    }

    func testCodegenStringIndexOperatorUsesStringGet() throws {
        let source = """
        fun main() {
            val s = "hello"
            println(s[0])
            println(s[4])
        }
        """

        try assertKotlinOutput(source, moduleName: "StringIndexOperator", expected: "h\no\n")
    }
}


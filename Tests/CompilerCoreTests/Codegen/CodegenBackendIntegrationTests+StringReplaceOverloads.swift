@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenStringReplaceOverloads() throws {
        let source = """
        fun main() {
            println("hello world".replace('l', 'r'))
            println("Hello World".replace("hello", "Hi", ignoreCase = true))
            println("Hello World".replace("hello", "Hi", ignoreCase = false))
            println("Hello World".replace('h', 'J', ignoreCase = true))
            println("Hello World".replace('H', 'J', ignoreCase = false))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringReplaceOverloads",
            expected:
                """
                herro worrd
                Hi World
                Hello World
                Jello World
                Jello World
                """
                + "\n"
        )
    }
}


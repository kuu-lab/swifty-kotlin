@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenThrowableSuppressedExceptionsProperty() throws {
        let source = """
        fun main() {
            val primary = RuntimeException("primary")
            primary.addSuppressed(IllegalStateException("suppressed1"))
            primary.addSuppressed(IllegalArgumentException("suppressed2"))

            val suppressed = primary.suppressedExceptions
            println(suppressed.size)
            println(suppressed[0].message)
            println(suppressed[1].message)
        }
        """

        try assertKotlinOutput(source, moduleName: "ThrowableSuppressedExceptionsRuntime", expected: "2\nsuppressed1\nsuppressed2\n")
    }
}


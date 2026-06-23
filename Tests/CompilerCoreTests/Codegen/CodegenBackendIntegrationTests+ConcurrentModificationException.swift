@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCatchesConcurrentModificationException() throws {
        let source = """
        fun main() {
            try {
                throw ConcurrentModificationException("modified")
            } catch (e: ConcurrentModificationException) {
                println("concurrent")
            }

            try {
                throw ConcurrentModificationException()
            } catch (e: RuntimeException) {
                println("runtime")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ConcurrentModificationExceptionCase", expected: "concurrent\nruntime\n")
    }
}


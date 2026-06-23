@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCatchesArrayIndexOutOfBoundsException() throws {
        let source = """
        fun main() {
            try {
                throw ArrayIndexOutOfBoundsException("bad index")
            } catch (e: ArrayIndexOutOfBoundsException) {
                println("array-index")
            }

            try {
                throw ArrayIndexOutOfBoundsException()
            } catch (e: IndexOutOfBoundsException) {
                println("index")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayIndexOutOfBoundsExceptionCase", expected: "array-index\nindex\n")
    }
}


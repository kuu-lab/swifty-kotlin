@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendArrayIndexOutOfBoundsExceptionTests {
    @Test
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

#endif

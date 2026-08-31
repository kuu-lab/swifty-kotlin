@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendNoWhenBranchMatchedExceptionTests {

    @Test
    func testCodegenCatchesNoWhenBranchMatchedException() throws {
        let source = """
        fun main() {
            try {
                throw NoWhenBranchMatchedException("missing")
            } catch (e: NoWhenBranchMatchedException) {
                println("no-when")
            }

            try {
                throw NoWhenBranchMatchedException()
            } catch (e: RuntimeException) {
                println("runtime")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "NoWhenBranchMatchedExceptionCase", expected: "no-when\nruntime\n")
    }
}
#endif

@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendNoWhenBranchMatchedExceptionTests {

    @Test(arguments: [true, false])
    func testCodegenNoWhenBranchMatchedExceptionMessages(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("kuu1326_no_when_branch_matched_exception.kt")

        try assertKotlinOutput(
            source,
            moduleName: "NoWhenBranchMatchedExceptionMessages",
            expected: "null\nnull\nmissing\nnull\ntrue\nexplicit\ntrue\njava.lang.RuntimeException: cause\ntrue\nnull\ntrue\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

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

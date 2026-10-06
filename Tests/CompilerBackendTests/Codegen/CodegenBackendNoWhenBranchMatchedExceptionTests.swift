@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendNoWhenBranchMatchedExceptionTests {

    @Test(arguments: [true, false])
    func testCodegenNoWhenBranchMatchedExceptionMessages(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        fun main() {
            val cause = RuntimeException("cause")
            println(NoWhenBranchMatchedException().message)
            println(NoWhenBranchMatchedException(null as String?).message)
            println(NoWhenBranchMatchedException("missing").message)
            val withCause = NoWhenBranchMatchedException(null, cause)
            println(withCause.message)
            println(withCause.cause === cause)
            val explicitMessage = NoWhenBranchMatchedException("explicit", cause)
            println(explicitMessage.message)
            println(explicitMessage.cause === cause)
            val causeOnly = NoWhenBranchMatchedException(cause)
            println(causeOnly.message)
            println(causeOnly.cause === cause)
            println(NoWhenBranchMatchedException(null as Throwable?).message)
            println(NoWhenBranchMatchedException(null, null).cause == null)
        }
        """

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

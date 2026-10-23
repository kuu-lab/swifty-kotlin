#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendFinallyExceptionRoutingTests {

    @Test(arguments: [true, false])
    func testKUU2840InlineFinallyExceptionsSkipExitedTryHandlers(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("kuu2840_exception_thrown_in_finally.kt")
        try assertKotlinOutput(
            source,
            moduleName: "KUU2840FinallyExceptionRouting",
            expected: "break finally\ncontinue finally\nreturn finally\nouter finally outer-catch\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif

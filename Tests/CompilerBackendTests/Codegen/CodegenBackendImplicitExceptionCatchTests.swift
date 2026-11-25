#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendImplicitExceptionCatchTests {

    @Test(arguments: [true, false])
    func testNonNullAssertionsUseCatchableNPEChannel(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("kuu995_non_null_assertion_catch.kt")
        try assertKotlinOutput(
            source,
            moduleName: "NonNullAssertionCatch",
            expected:
                """
                NPE caught
                E caught: true
                T caught: true
                Int NPE caught
                String function caught
                Int function caught
                inner finally
                outer NPE caught
                outer finally
                ok
                42
                end
                """ + "\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif

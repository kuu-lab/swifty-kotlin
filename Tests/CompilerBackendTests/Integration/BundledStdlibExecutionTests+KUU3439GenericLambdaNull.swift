#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testKuu3439NullableValueClassPayloadFromGenericLambda() throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3439_nullable_any_generic_lambda_null.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU3439NullableValueClassPayloadFromGenericLambda",
            expectedStderr: ""
        )
    }
}
#endif

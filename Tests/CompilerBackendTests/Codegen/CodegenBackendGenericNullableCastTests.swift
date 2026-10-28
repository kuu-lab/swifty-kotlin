#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendGenericNullableCastTests {
    @Test
    func erasedGenericResultsCheckNullablePrimitiveAndReferenceClaims() throws {
        let source = try diffCaseSource("kuu_3171_nullable_generic_as_cast.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "GenericNullableAsCast",
            expected: "OK\nOK\n42\n"
        )
    }
}
#endif

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
            expected: "marker\nOK\n42\n"
        )
    }

    @Test
    func nullAsUnboundedTypeParameterCrossesErasedClaimAsNull() throws {
        let source = try diffCaseSource("null_as_generic_type_parameter.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "NullAsGenericTypeParameter",
            expected: "int:OK\nstr:OK\nbounded:NPE\niface:NPE\n"
        )
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendNonNullableCallNullComparisonTests {
    @Test
    func testNonNullablePrimitiveCallComparedToNullPreservesSideEffects() throws {
        let source = """
        var result = "fail"
        fun withSideEffect(): Int {
            result = "OK"
            return 42
        }

        fun main() {
            if (withSideEffect() == null) { }
            println(result)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NonNullableCallNullComparisonSideEffects",
            expected: "OK\n"
        )
    }
}
#endif

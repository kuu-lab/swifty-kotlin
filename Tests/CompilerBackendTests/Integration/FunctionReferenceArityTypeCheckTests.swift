#if canImport(Testing)
import Foundation
@testable import CompilerCore
import Testing

@Suite
struct FunctionReferenceArityTypeCheckTests {
    @Test
    func callableReferenceIsChecksRespectFunctionNArity() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Scripts/diff_cases/kuu_3536_function_reference_arity_is.kt"
            ),
            encoding: .utf8
        )

        try assertKotlinOutput(
            source,
            moduleName: "KUU3536FunctionReferenceArity",
            expected: "good\ngood\n"
        )
    }
}
#endif

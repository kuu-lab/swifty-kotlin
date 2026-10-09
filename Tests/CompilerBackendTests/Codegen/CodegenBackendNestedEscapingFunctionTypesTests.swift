@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendNestedEscapingFunctionTypesTests {
    @Test
    func codegenNestedEscapingFunctionTypeBooleanComparison() throws {
        let source = KotlinSourceFixtures.nestedEscapingFunctionTypeBooleanComparison

        try assertKotlinOutput(
            source,
            moduleName: "NestedEscapingFunctionTypes",
            expected:
                """
                false
                false
                """
                + "\n"
        )
    }

}

#endif

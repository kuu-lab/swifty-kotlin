@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendSequenceSingleTests {

    @Test
    func codegenSequenceSingleUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_single.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSingle",
            expected:
                """
                42
                only
                """
                + "\n"
        )
    }
}
#endif

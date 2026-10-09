@testable import CompilerBackend
import Testing

@Suite
struct CodegenRuntimeSupportHashTests {
    @Test
    func runtimeIdentifierHashKeepsItsUnpaddedFormat() {
        let value = CodegenRuntimeSupport.stableFNV1a64Hex("leading-zero-200")

        #expect(value == "fc5ecb561a3e7f9")
        #expect(value.count == 15)
    }
}

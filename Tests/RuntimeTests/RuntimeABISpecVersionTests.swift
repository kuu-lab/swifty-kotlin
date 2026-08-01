#if canImport(Testing)
import RuntimeABI
import Testing

@Suite
struct RuntimeABISpecVersionTests {
    /// `RuntimeABISpec.specVersion` is now derived from `allFunctions` at first access,
    /// so this test verifies the value is a valid 64-character SHA-256 hex string and stable.
    @Test
    func testSpecVersionIsValidAndDeterministic() {
        let version = RuntimeABISpec.specVersion
        #expect(
            version.count == 64,
            "specVersion must be a 64-character SHA-256 hex string"
        )
        #expect(
            version.allSatisfy { $0.isHexDigit },
            "specVersion must contain only hex digits"
        )
        #expect(
            version == RuntimeABISpec.specVersion,
            "specVersion must be deterministic across repeated accesses"
        )
    }
}
#endif

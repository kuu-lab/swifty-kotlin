#if canImport(Testing)
import RuntimeABI
import Testing

@Suite
struct RuntimeABISyntheticStubTests {
    /// Vararg synthetic stubs pass their arguments as one packed array handle.
    @Test
    func testSequenceOfUsesPackedArrayABI() throws {
        let specs = RuntimeABISpec.sequenceFunctions.filter { $0.name.hasSuffix("_sequence_of") }
        try #require(specs.count == 1, "Expected one sequence factory ABI declaration")
        let extern = try #require(
            RuntimeABIExterns.externDecl(named: specs[0].name)
        )

        #expect(
            extern.parameterTypes == [RuntimeABICType.intptr.rawValue],
            "Sequence vararg factory must accept one packed array handle"
        )
    }
}
#endif

#if canImport(Testing)
import RuntimeABI
import Testing

@Suite
struct RuntimeABISyntheticStubTests {
    /// Vararg synthetic stubs pass their arguments as one packed array handle.
    @Test
    func testSequenceOfUsesPackedArrayABI() throws {
        let extern = try #require(
            RuntimeABIExterns.externDecl(named: "kk_sequence_of")
        )

        #expect(
            extern.parameterTypes == [RuntimeABICType.intptr.rawValue],
            "kk_sequence_of must accept one packed array handle"
        )
    }
}
#endif

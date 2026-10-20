#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [
        "string_api_contract_negative_pad",
        "string_padding_validation_boundaries"
    ], JVMSequenceAuditLane.allCases)
    func stringPaddingRejectsNegativeLengths(name: String, lane: JVMSequenceAuditLane) throws {
        try runSequenceAuditFixture(name, lane: lane)
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [
        "regex_split_limit",
        "kuu_635_regex_split_limit",
        "regex_split_validation_boundaries"
    ], JVMSequenceAuditLane.allCases)
    func regexSplitLimitsPreserveValidationMessages(name: String, lane: JVMSequenceAuditLane) throws {
        try runSequenceAuditFixture(name, lane: lane)
    }
}
#endif

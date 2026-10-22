#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [
        "seq_mapindexed_throw_retry",
        "seq_oneachindexed_throw_retry",
        "sequence_mapindexednotnull_throw_retry",
        "sequence_filterindexed_throw_retry",
        "control_indexed_normal",
        "sequence_indexed_source_failure"
    ], JVMSequenceAuditLane.allCases)
    func sequenceIndexedCallbacksAdvanceBeforeExceptions(name: String, lane: JVMSequenceAuditLane) throws {
        try runSequenceAuditFixture(name, lane: lane)
    }
}
#endif

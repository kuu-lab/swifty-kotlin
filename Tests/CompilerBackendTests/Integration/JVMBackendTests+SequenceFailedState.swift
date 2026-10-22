#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [
        "seq_zipwithnext_throw_retry",
        "sequence_windowed_source_failure",
        "control_zipwithnext_normal",
        "control_windowed_transform_failure",
        "control_chunked_transform_failure",
        "sequence_builder_failure_state",
        "sequence_internal_failure_boundaries"
    ], JVMSequenceAuditLane.allCases)
    func sequenceInternalFailuresPoisonIterators(name: String, lane: JVMSequenceAuditLane) throws {
        try runSequenceAuditFixture(name, lane: lane)
    }
}
#endif

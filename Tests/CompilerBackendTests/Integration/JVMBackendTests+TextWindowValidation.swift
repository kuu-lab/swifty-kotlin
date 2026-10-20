#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [
        "stdlib_kotlin_text_CharSequence_chunked",
        "text_window_validation_boundaries"
    ], JVMSequenceAuditLane.allCases)
    func textWindowSizesPreserveValidationMessages(name: String, lane: JVMSequenceAuditLane) throws {
        try runSequenceAuditFixture(name, lane: lane)
    }
}
#endif

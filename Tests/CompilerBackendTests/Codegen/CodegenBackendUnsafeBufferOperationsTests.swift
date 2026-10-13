#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendUnsafeBufferOperationsTests {

    private func source(_ filename: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/diff_cases/\(filename)"),
            encoding: .utf8
        )
    }

    @Test
    func portAllCommonUnsafeUpstreamTestFunctions() throws {
        try assertKotlinOutput(
            source("kotlinx_io_unsafe_buffer_ops_upstream.kt"),
            moduleName: "UnsafeBufferOperationsUpstreamPorts",
            expected: "forEach:pass\niteration:pass\nmove:pass\nread:pass\nwrite:pass\n"
        )
    }

    @Test
    func compareCallbackCapacityCommitAndExceptionStates() throws {
        try assertKotlinOutput(
            source("kotlinx_io_unsafe_buffer_ops_boundaries.kt"),
            moduleName: "UnsafeBufferOperationsBoundaries",
            expected: "capacityAndZeroCommit:pass\nreadCommitBoundaries:pass\n"
                + "writeCommitBoundaries:pass\ncallbackExceptionState:pass\n"
        )
    }

    @Test
    func nestedInlineReturnPreservesFollowingBufferIO() throws {
        try assertKotlinOutput(
            source("kotlinx_io_unsafe_buffer_ops.kt"),
            moduleName: "UnsafeBufferOperationsNestedInline",
            expected: "8192\n5\n60\n3\n2\n2\n4\n105\nkotlin.Unit\nkotlin.Unit\n2\n2\n7\n6\n1\ntrue\n40\n2\n8\n7,8,1,2,3,4,5,6\n0\ntrue\n"
        )
    }
}
#endif

// STDLIB-UUID-FN-002: End-to-end codegen tests for ByteArray.putUuid and ByteArray.uuid(at:).
// Note: ByteArray(size) constructor is not yet supported; tests use Uuid.toByteArray()
// as a mutable 16-byte buffer source.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    // MARK: - uuid(at:): read NIL UUID from its own byte representation

    func testCodegenUuidAtReadsNilUuidFromByteArray() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.uuid

        fun main() {
            // Uuid.NIL.toByteArray() produces 16 zero bytes.
            // uuid(0) on that ByteArray must reconstruct the NIL UUID.
            val nilBytes = Uuid.NIL.toByteArray()
            val readback = nilBytes.uuid(0)
            println(readback.toString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(Foundation.UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UuidAtReadsNilUuid",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "00000000-0000-0000-0000-000000000000\n")
        }
    }

    // MARK: - putUuid / uuid(at:) round-trip preserves UUID value

    func testCodegenUuidPutUuidRoundTripPreservesValue() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid
        import kotlin.uuid.uuid

        fun main() {
            val original = Uuid.fromLongs(0L, 1L)
            // Use NIL's byte buffer as a writable 16-byte scratch space.
            val buf = Uuid.NIL.toByteArray()
            buf.putUuid(0, original)
            val readback = buf.uuid(0)
            println(readback.toString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(Foundation.UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UuidPutUuidRoundTrip",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            // fromLongs(0L, 1L): MSB=0, LSB=1  →  "00000000-0000-0000-0000-000000000001"
            XCTAssertEqual(out, "00000000-0000-0000-0000-000000000001\n")
        }
    }

    // MARK: - putUuid overwrites a buffer with known UUID bytes

    func testCodegenUuidPutUuidOverwritesBuffer() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid
        import kotlin.uuid.uuid

        fun main() {
            val uuid = Uuid.fromLongs(0x0102030405060708L, 0x090a0b0c0d0e0f10L)
            val buf = Uuid.NIL.toByteArray()
            buf.putUuid(0, uuid)
            // Verify the first and last bytes were written correctly.
            println(buf[0])   // 0x01 = 1
            println(buf[15])  // 0x10 = 16
            // Round-trip: reading the UUID back must match the original.
            val readback = buf.uuid(0)
            println(readback.toString())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(Foundation.UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UuidPutUuidOverwritesBuffer",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            // fromLongs(0x0102030405060708, 0x090a0b0c0d0e0f10)
            // UUID: 01020304-0506-0708-090a-0b0c0d0e0f10
            XCTAssertEqual(out, "1\n16\n01020304-0506-0708-090a-0b0c0d0e0f10\n")
        }
    }
}

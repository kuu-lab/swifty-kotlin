@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenUuidAtReadsNilUuidFromByteBuffer() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.getUuid
        import java.nio.ByteBuffer

        fun main() {
            val nilBytes = Uuid.NIL.toByteArray()
            val buf = ByteBuffer.wrap(nilBytes)
            val readback = buf.getUuid(0)
            println(readback.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "UuidAtReadsNilUuid", expected: "00000000-0000-0000-0000-000000000000\n")
    }

    func testCodegenUuidPutUuidRoundTripPreservesValue() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid
        import kotlin.uuid.getUuid
        import java.nio.ByteBuffer

        fun main() {
            val original = Uuid.fromLongs(0L, 1L)
            val buf = ByteBuffer.wrap(Uuid.NIL.toByteArray())
            buf.putUuid(0, original)
            val readback = buf.getUuid(0)
            println(readback.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "UuidPutUuidRoundTrip", expected: "00000000-0000-0000-0000-000000000001\n")
    }

    func testCodegenUuidPutUuidOverwritesBuffer() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid
        import kotlin.uuid.getUuid
        import java.nio.ByteBuffer

        fun main() {
            val uuid = Uuid.fromLongs(0x0102030405060708L, 0x090a0b0c0d0e0f10L)
            val buf = ByteBuffer.wrap(Uuid.NIL.toByteArray())
            buf.putUuid(0, uuid)
            println(buf.get(0))
            println(buf.get(15))
            val readback = buf.getUuid(0)
            println(readback.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "UuidPutUuidOverwritesBuffer", expected: "1\n16\n01020304-0506-0708-090a-0b0c0d0e0f10\n")
    }
}

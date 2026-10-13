#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-1367: the bundled `kotlinx.io` surface mirrors upstream kotlinx-io 0.9.1,
/// where `ByteString.hex()`, `ByteString.utf8()`,
/// `ByteArray.encodeToByteString()`, `Buffer.snapshot(byteCount)`, and
/// `ByteString` iteration do not exist — they are okio APIs, not kotlinx-io.
/// Real kotlinc + kotlinx-io 0.9.1 rejects every one of them, so the bundled
/// surface must keep rejecting them too. The real kotlinx-io members
/// (`snapshot()`, `toHexString()`, `decodeToString()`, `encodeToByteString()`
/// on `String`) must keep resolving.
@Suite
struct KotlinxIOByteStringSurfaceTests {
    @Test
    func realKotlinxIoByteStringSurfaceResolves() throws {
        let source = """
        import kotlinx.io.*
        import kotlinx.io.bytestring.*

        fun use(buffer: Buffer, bytes: ByteString): Int {
            val full = buffer.snapshot()
            val hex = bytes.toHexString()
            val text = bytes.decodeToString()
            val roundtrip = "hi".encodeToByteString()
            val parsed = "00ff".hexToByteString()
            val first = bytes[0]
            val range = bytes.indices
            return full.size + hex.length + text.length + roundtrip.size +
                parsed.size + first + range.count
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func okioOnlyByteStringMembersStayRejected() throws {
        let source = """
        import kotlinx.io.*
        import kotlinx.io.bytestring.*

        fun use(buffer: Buffer, bytes: ByteString) {
            bytes.hex()
            bytes.utf8()
            byteArrayOf(1).encodeToByteString()
            buffer.snapshot(2)
            for (b in bytes) { println(b) }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let codes = ctx.diagnostics.diagnostics
            .filter { $0.severity == .error }
            .map(\.code)
            .sorted()
        #expect(codes == [
            "KSWIFTK-SEMA-0002",
            "KSWIFTK-SEMA-0024",
            "KSWIFTK-SEMA-0024",
            "KSWIFTK-SEMA-0024",
            "KSWIFTK-SEMA-0172",
        ], "\(ctx.diagnostics.diagnostics)")
    }
}
#endif

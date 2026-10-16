#if os(macOS)
@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite(.serialized)
struct KotlinNativePosixFoundationExecutionTests {
    @Test
    func posixErrnoByteOrderAndFoundationCharsetRoundTrip() throws {
        TestStdlibCache.shared.prepare()
        let level = try #require(OptimizationLevel(rawValue: 0))
        try compileAndRunKotlin(
            """
            @file:Suppress("CAST_NEVER_SUCCEEDS")
            @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class,
                kotlinx.cinterop.ExperimentalForeignApi::class)

            import kotlin.experimental.*
            import kotlinx.cinterop.*
            import platform.Foundation.*
            import platform.posix.*

            fun main() {
                if (access("", F_OK) != -1 || errno != ENOENT) error("POSIX errno mismatch")
                println("errno=true")

                if (!Platform.isLittleEndian) error("Unexpected macOS byte order")
                println("little=true")

                val text = "Kotlin café 🍵"
                val bytes = text.encodeToByteArray()
                if (!byteArrayOf().isEmpty() || byteArrayOf(1).isEmpty()) error("ByteArray.isEmpty mismatch")
                println("byte-array-empty=true")

                val pointerSource = byteArrayOf(1, 2, 3)
                val pointerCopy = ByteArray(2)
                pointerSource.usePinned { sourcePinned ->
                    pointerCopy.usePinned { destinationPinned ->
                        memcpy(destinationPinned.addressOf(0), sourcePinned.addressOf(0) + 1L, 2uL)
                    }
                }
                if (pointerCopy[0] != 2.toByte() || pointerCopy[1] != 3.toByte()) {
                    error("Long C pointer arithmetic or memcpy mismatch")
                }
                println("pointer-add=true")

                val mutableData = NSMutableData()
                bytes.usePinned { mutableData.appendBytes(it.addressOf(0), bytes.size.toULong()) }
                val decoded = NSString.create(mutableData, NSUTF8StringEncoding)
                    ?: error("Foundation UTF-8 decode failed")
                if (decoded != text) error("Foundation UTF-8 decode changed bytes")

                val encoded = (text as? NSString)?.dataUsingEncoding(NSUTF8StringEncoding)
                    ?: error("Foundation UTF-8 encode failed")
                if (encoded.length != bytes.size.toULong()) error("Foundation UTF-8 length mismatch")
                println("utf8=true")
            }
            """,
            expectedOutput: "errno=true\nlittle=true\nbyte-array-empty=true\npointer-add=true\nutf8=true\n",
            allowDefaultStdlibLibrary: true,
            optLevel: level
        )
    }
}
#endif

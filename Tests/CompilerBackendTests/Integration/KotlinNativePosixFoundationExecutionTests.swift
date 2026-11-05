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

    @Test
    func nsDataCompressionAndMutableDataCreateLengthRoundTrip() throws {
        TestStdlibCache.shared.prepare()
        let level = try #require(OptimizationLevel(rawValue: 0))
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

            import kotlinx.cinterop.*
            import platform.Foundation.*

            fun main() {
                val text = "Compress me, please!"
                val bytes = text.encodeToByteArray()

                val data = NSMutableData()
                bytes.usePinned { data.appendBytes(it.addressOf(0), bytes.size.toULong()) }

                val compressed = data.compressedDataUsingAlgorithm(
                    algorithm = NSDataCompressionAlgorithmZlib,
                    error = null
                )!!
                val hex = StringBuilder()
                val raw = compressed.bytes!!
                for (index in 0 until compressed.length.toInt()) {
                    val value = raw[index].toInt() and 0xFF
                    hex.append((value shr 4).toString(16)).append((value and 0xF).toString(16))
                }
                println("zlib-hex=${hex.toString() == "73cecf2d284a2d2e56c84dd55128c8494d2c4e550400"}")

                val decompressed = compressed.decompressedDataUsingAlgorithm(
                    algorithm = NSDataCompressionAlgorithmZlib,
                    error = null
                )!!
                println("roundtrip=${NSString.create(decompressed, NSUTF8StringEncoding) == text}")

                for (algorithm in listOf(NSDataCompressionAlgorithmLZFSE,
                                         NSDataCompressionAlgorithmLZ4,
                                         NSDataCompressionAlgorithmLZMA,
                                         NSDataCompressionAlgorithmZlib)) {
                    val packed = data.compressedDataUsingAlgorithm(algorithm = algorithm, error = null)
                    val unpacked = packed?.decompressedDataUsingAlgorithm(algorithm = algorithm, error = null)
                    println("algo-$algorithm=${packed != null && unpacked != null && unpacked.length == data.length.toULong()}")
                }

                val readData = NSMutableData.create(length = 100.convert())!!
                println("created=${readData.length == 100uL}")
                readData.appendBytes(compressed.bytes, compressed.length)
                println("appended=${readData.length == 100uL + compressed.length}")
            }
            """,
            expectedOutput: "zlib-hex=true\nroundtrip=true\n" +
                "algo-0=true\nalgo-1=true\nalgo-2=true\nalgo-3=true\n" +
                "created=true\nappended=true\n",
            allowDefaultStdlibLibrary: true,
            optLevel: level
        )
    }
}
#endif

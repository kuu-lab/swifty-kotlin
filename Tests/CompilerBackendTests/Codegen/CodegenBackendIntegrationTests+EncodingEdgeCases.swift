@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesEncodingEdgeCases() throws {
        let source = """
        @OptIn(ExperimentalStdlibApi::class)
        fun main() {
            val original = "こんにちは"
            val encoded = original.encodeToByteArray()
            println(encoded.decodeToString())

            val ascii = "ABC".encodeToByteArray()
            println(String(ascii, Charsets.US_ASCII))

            val hex = 255.toHexString()
            println(hex)
            println(hex.hexToInt())
            println("ffff".hexToShort())
            println("ff".hexToUByte().toInt())
            println("ffff".hexToUShort().toInt())
            println("ff".toUByteOrNull(16)?.toInt() ?: -1)
            println("100".toUByteOrNull(16)?.toInt() ?: -1)
            println("ffff".toUShortOrNull(16)?.toInt() ?: -1)
            println("10000".toUShortOrNull(16)?.toInt() ?: -1)
            println("ffffffff".toUIntOrNull(16)?.toLong() ?: -1L)
            println("100000000".toUIntOrNull(16)?.toLong() ?: -1L)
            println("ffffffffffffffff".toULongOrNull(16) ?: 0uL)
            println("10000000000000000".toULongOrNull(16) ?: 1uL)
            println("ffffffff".hexToUInt())
            println("ffffffffffffffff".hexToULong())
            val ubytes = "00ff".hexToUByteArray()
            println(ubytes.size)
            println(ubytes[1])
            try {
                println("gg".hexToInt())
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EncodingEdgeCases",
            expected:
                """
                こんにちは
                ABC
                000000ff
                255
                -1
                255
                65535
                255
                -1
                65535
                -1
                4294967295
                -1
                18446744073709551615
                1
                4294967295
                18446744073709551615
                2
                255
                caught
                """
                + "\n"
        )
    }

    /// KSP-481: HexFormat customization (byteSeparator/prefix/suffix/removeLeadingZeros)
    /// is only reachable through the ordinary named-argument constructor here, not the
    /// `HexFormat { }` builder lambda real kotlinc supports -- see the constraints
    /// documented at the top of Stdlib/kotlin/io/encoding/HexFormat.kt. That gap keeps
    /// this scenario out of Scripts/diff_cases (which requires kotlinc parity), so it is
    /// pinned here against a hardcoded expected output instead.
    func testCodegenCompilesHexFormatCustomization() throws {
        let source = """
        @OptIn(ExperimentalStdlibApi::class)
        fun main() {
            val fmt = HexFormat(upperCase = true, byteSeparator = ":", prefix = "0x", suffix = "h", removeLeadingZeros = true)
            println(byteArrayOf(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte()).toHexString(fmt))
            val encodedInt = 255.toHexString(fmt)
            println(encodedInt)
            println(encodedInt.hexToInt(fmt))
            val encodedLong = 4096L.toHexString(fmt)
            println(encodedLong)
            println(encodedLong.hexToLong(fmt))
            println(0.toHexString(HexFormat(removeLeadingZeros = true)))
            try {
                "ff".hexToInt(HexFormat(prefix = "0x"))
            } catch (e: NumberFormatException) {
                println("missing-prefix")
            }
            try {
                "abc".hexToByteArray()
            } catch (e: NumberFormatException) {
                println("odd-length")
            }
            println(HexFormat.Default.upperCase)
            println(HexFormat(byteSeparator = "-").bytes.byteSeparator)
            val custom = HexFormat()
            custom.number.prefix = "0x"
            println(255.toHexString(custom))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "HexFormatCustomization",
            expected:
                """
                DE:AD:BE
                0xFFh
                255
                0x1000h
                4096
                0
                missing-prefix
                odd-length
                false
                -
                0x000000ff
                """
                + "\n"
        )
    }

    func testCodegenCompilesDecodeToStringRangeEdgeCases() throws {
        let source = """
        fun main() {
            val bytes = "abcdef".encodeToByteArray()
            println(bytes.decodeToString(1, 4))
            println(bytes.decodeToString(0, 6, true))

            val malformed = byteArrayOf((-61).toByte(), 40.toByte())
            println(malformed.decodeToString(0, 2, false).length > 0)
            try {
                println(malformed.decodeToString(0, 2, true))
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DecodeToStringRangeEdgeCases",
            expected:
                """
                bcd
                abcdef
                true
                caught
                """
                + "\n"
        )
    }
}


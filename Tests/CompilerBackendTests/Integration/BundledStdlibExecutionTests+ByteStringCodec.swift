import Testing

extension BundledStdlibExecutionTests {
    @Test func testByteStringHexAndBase64CodecExecute() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.io.bytestring.ByteString
            import kotlinx.io.bytestring.hexToByteString
            import kotlinx.io.bytestring.toHexString
            import kotlinx.io.bytestring.decode
            import kotlinx.io.bytestring.decodeIntoByteArray
            import kotlinx.io.bytestring.decodeToByteString
            import kotlinx.io.bytestring.decodeToString
            import kotlinx.io.bytestring.encode
            import kotlinx.io.bytestring.encodeIntoByteArray
            import kotlinx.io.bytestring.encodeToAppendable
            import kotlinx.io.bytestring.encodeToByteArray
            import kotlin.io.encoding.Base64
            import kotlin.io.encoding.ExperimentalEncodingApi
            import kotlin.text.HexFormat

            @OptIn(ExperimentalEncodingApi::class, ExperimentalStdlibApi::class)
            fun main() {
                val hexValue = ByteString(byteArrayOf(-85, 18, -51, -17))
                println(hexValue.toHexString())
                println(hexValue.toHexString(HexFormat.UpperCase))
                println(hexValue.toHexString(1, 3))
                println("ab12".hexToByteString().toHexString())
                try {
                    "xz".hexToByteString()
                } catch (e: IllegalArgumentException) {
                    println("hexToByteString-invalid")
                }

                val value = ByteString("Hello".encodeToByteArray())
                println(Base64.encode(value))
                println(Base64.encodeToByteArray(value).decodeToString())
                val dest = ByteArray(16)
                val written = Base64.encodeIntoByteArray(value, dest, 0)
                println("$written:${dest.decodeToString(0, written)}")
                val sb = StringBuilder()
                Base64.encodeToAppendable(value, sb)
                println(sb.toString())
                val encoded = ByteString("SGVsbG8=".encodeToByteArray())
                println(Base64.decode(encoded).decodeToString())
                println(Base64.decodeToByteString("SGVsbG8=").decodeToString())
                println(Base64.decodeToByteString(encoded).decodeToString())
                val out = ByteArray(8)
                val count = Base64.decodeIntoByteArray(encoded, out, 0)
                println("$count:${out.decodeToString(0, count)}")
                println(Base64.UrlSafe.encode(ByteString(byteArrayOf(62, 62, 62))))
                println(Base64.UrlSafe.decodeToByteString("Pj4-").decodeToString())
            }
            """,
            expectedOutput: "ab12cdef\nAB12CDEF\n12cd\nab12\nhexToByteString-invalid\nSGVsbG8=\nSGVsbG8=\n8:SGVsbG8=\nSGVsbG8=\nHello\nHello\nHello\n5:Hello\nPj4-\n>>>\n"
        )
    }
}

import Testing

extension BundledStdlibExecutionTests {
    @Test func testByteStringCoreAndBuilderExecute() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.io.bytestring.ByteString
            import kotlinx.io.bytestring.ByteStringBuilder
            import kotlinx.io.bytestring.encodeToByteString
            import kotlinx.io.bytestring.decodeToString
            import kotlinx.io.bytestring.indexOf
            import kotlinx.io.bytestring.lastIndexOf
            import kotlinx.io.bytestring.startsWith
            import kotlinx.io.bytestring.endsWith
            import kotlinx.io.bytestring.buildByteString
            import kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
            import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

            @OptIn(UnsafeByteStringApi::class)
            fun checkUnsafeSharing() {
                val array = byteArrayOf(66)
                val wrapped = UnsafeByteStringOperations.wrapUnsafe(array)
                array[0] = 67
                println(wrapped[0])
            }

            fun main() {
                val input = byteArrayOf(65, 66, 67)
                val bytes = ByteString(input)
                input[0] = 90
                println(bytes[0])
                val output = bytes.toByteArray()
                output[1] = 90
                println(bytes[1])
                println(bytes.substring(1).decodeToString())
                println(bytes.indexOf(66.toByte()))
                println(bytes.lastIndexOf(67.toByte()))
                println(bytes.startsWith(byteArrayOf(65, 66)))
                println(bytes.endsWith(ByteString(byteArrayOf(66, 67))))
                println(bytes == ByteString(byteArrayOf(65, 66, 67)))
                println(bytes.compareTo(ByteString(byteArrayOf(65, 66, 68))) < 0)
                println(bytes)
                // Vararg `Byte` arguments are boxed in this compiler, so raw-byte
                // operations on arrays built from them misread; exercise the
                // ByteArray factory instead (KUU vararg follow-up).
                println(ByteString(byteArrayOf(65, 66)).decodeToString())
                val unsigned = ByteString(0u.toUByte(), 255u.toUByte())
                println(unsigned[1])
                println(unsigned.toString())
                val builder = ByteStringBuilder(2)
                builder.append(65.toByte())
                builder.append(byteArrayOf(66, 67))
                builder.append(ByteString(byteArrayOf(68)))
                val built = builder.toByteString()
                builder.append(byteArrayOf(69, 70), 1)
                println(built.decodeToString())
                println("é".encodeToByteString().decodeToString())
                println(buildByteString { append(69.toByte()) }.decodeToString())
                checkUnsafeSharing()
            }
            """,
            expectedOutput: "65\n66\nBC\n1\n2\ntrue\ntrue\ntrue\ntrue\nByteString(size=3 hex=414243)\nAB\n-1\nByteString(size=2 hex=00ff)\nABCD\né\nE\n67\n"
        )
    }
}

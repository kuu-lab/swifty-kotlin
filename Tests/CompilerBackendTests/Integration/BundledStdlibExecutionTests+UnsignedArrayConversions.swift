import Testing

extension BundledStdlibExecutionTests {
    // KUU-1421: signed<->unsigned primitive array copy conversions on both
    // primitive and boxed Array<out U*> receivers. Bit patterns are preserved
    // and the result owns fresh storage, so post-conversion mutation of either
    // side is invisible to the other.
    @Test(arguments: [true, false])
    func testUnsignedArrayCopyConversions(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            @OptIn(ExperimentalUnsignedTypes::class)
            fun main() {
                println(byteArrayOf(1, -1, 0, 127, -128).toUByteArray().toList())
                println(shortArrayOf(1, -1, 32767, -32768).toUShortArray().toList())
                println(longArrayOf(1L, -1L).toULongArray().toList())
                println(ubyteArrayOf(255.toUByte(), 0.toUByte(), 128.toUByte()).toByteArray().toList())
                println(ushortArrayOf(65535.toUShort(), 0.toUShort()).toShortArray().toList())
                println(uintArrayOf(4294967295u, 0u, 2147483648u).toIntArray().toList())
                println(ulongArrayOf(18446744073709551615uL, 0uL).toLongArray().toList())
                println(arrayOf(1.toUByte(), 255.toUByte()).toUByteArray().toList())
                println(arrayOf(1.toUShort(), 65535.toUShort()).toUShortArray().toList())
                println(arrayOf(1uL, 18446744073709551615uL).toULongArray().toList())
                val uself = ubyteArrayOf(1.toUByte(), 255.toUByte())
                val uselfCopy = uself.toUByteArray()
                uself[0] = 9.toUByte()
                println(uselfCopy.toList())
                println(ulongArrayOf(1uL).toULongArray().toList())

                val src = byteArrayOf(5, -5)
                val dst = src.toUByteArray()
                src[0] = 9
                dst[1] = 7.toUByte()
                println(src.toList())
                println(dst.toList())

                val usrc = ubyteArrayOf(200.toUByte())
                val udst = usrc.toByteArray()
                usrc[0] = 1.toUByte()
                udst[0] = 100
                println(usrc.toList())
                println(udst.toList())
            }
            """,
            expectedOutput: """
            [1, 255, 0, 127, 128]
            [1, 65535, 32767, 32768]
            [1, 18446744073709551615]
            [-1, 0, -128]
            [-1, 0]
            [-1, 0, -2147483648]
            [-1, 0]
            [1, 255]
            [1, 65535]
            [1, 18446744073709551615]
            [1, 255]
            [1]
            [9, -5]
            [5, 7]
            [1]
            [100]

            """,
            moduleName: "KUU1421UnsignedArrayConversions",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

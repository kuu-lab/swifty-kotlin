import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testStableHexFormatBuilder(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            // KUU-1106: Kotlin 2.2+ HexFormat APIs are stable without stdlib opt-in.
            fun main() {
                println(255.toHexString())
                println(255L.toHexString())
                println(byteArrayOf(1, 2).toHexString())
                println("ff".hexToInt())
                println("ff".hexToLong())
                println("ff".hexToShort())
                println("ff".hexToUByte())
                println("ff".hexToUShort())
                println("ff".hexToUInt())
                println("ff".hexToULong())
                println("0102".hexToByteArray().toHexString())
                println(byteArrayOf(1, 2, 3).toHexString(1, 3))
                println(HexFormat {}.upperCase)
                println(255.toHexString(HexFormat.UpperCase))
                val format = HexFormat {
                    upperCase = true
                    number {
                        prefix = "0x"
                        removeLeadingZeros = true
                        minLength = 4
                    }
                    bytes {
                        byteSeparator = ":"
                        bytePrefix = "["
                        byteSuffix = "]"
                    }
                }
                val byteOptions: HexFormat.BytesHexFormat = format.bytes
                val numberOptions: HexFormat.NumberHexFormat = format.number
                println(byteOptions.byteSeparator)
                println(numberOptions.minLength)
                println(255.toHexString(format))
                println("0x00FF".hexToInt(format))
                val encoded = byteArrayOf(1, -1).toHexString(format)
                println(encoded)
                println(encoded.hexToByteArray(format).toHexString())
                println(255.toHexString(HexFormat { number.removeLeadingZeros = true }))
            }
            """,
            expectedOutput: "000000ff\n00000000000000ff\n0102\n255\n255\n255\n255\n255\n255\n255\n0102\n0203\nfalse\n000000FF\n:\n4\n0x00FF\n255\n[01]:[FF]\n01ff\nff\n",
            moduleName: "KUU1106HexFormat",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

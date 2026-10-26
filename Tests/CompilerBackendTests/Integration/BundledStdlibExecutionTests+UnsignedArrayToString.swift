import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testUnsignedArrayToString() throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3307_unsigned_array_to_string.kt", file: #filePath),
            expectedOutput: """
            ULongArray(storage=[])
            ULongArray(storage=[0, -9223372036854775808, -1])
            ULongArray(storage=[0, -9223372036854775808, -1])
            UIntArray(storage=[0, -2147483648, -1])
            UIntArray(storage=[0, -2147483648, -1])
            UByteArray(storage=[0, -128, -1])
            UByteArray(storage=[0, -128, -1])
            UShortArray(storage=[0, -32768, -1])
            UShortArray(storage=[0, -32768, -1])
            ULongArray(storage=[0, -9223372036854775808, -1])
            UIntArray(storage=[0, -2147483648, -1])
            UByteArray(storage=[0, -128, -1])
            UShortArray(storage=[0, -32768, -1])

            """,
            moduleName: "KUU3307UnsignedArrayToString",
            allowDefaultStdlibLibrary: true
        )
    }
}

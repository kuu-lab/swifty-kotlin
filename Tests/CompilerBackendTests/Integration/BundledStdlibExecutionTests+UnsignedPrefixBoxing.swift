import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func unsignedPrefixIncrementDecrementBoxesIntoAny(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2917_unsigned_prefix_increment_decrement_boxing.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU2917UnsignedPrefixBoxing",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func ulongNarrowLiteralSlotBoxesAsULongIntoAny(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3790_ulong_narrow_literal_incdec_boxing.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU3790ULongNarrowLiteralBoxing",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

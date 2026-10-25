import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testStringCharToHashSetPreservesCharacterValues(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("string_char_to_hashset.kt", file: #filePath),
            expectedOutput: "[a, b]\n[a, b]\n[a, b]\n",
            moduleName: "StringCharToHashSet",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

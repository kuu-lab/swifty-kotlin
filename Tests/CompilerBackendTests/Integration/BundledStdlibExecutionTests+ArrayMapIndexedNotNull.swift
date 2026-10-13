import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testArrayMapIndexedNotNull(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("array_map_indexed_not_null.kt", file: #filePath),
            expectedOutput: try diffCaseSource("array_map_indexed_not_null.expected", file: #filePath),
            moduleName: "KUU1891ArrayMapIndexedNotNull",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

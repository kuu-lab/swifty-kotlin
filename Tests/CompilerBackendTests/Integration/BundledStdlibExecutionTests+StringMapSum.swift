import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testStringMapThenSumUsesListSum(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("string_map_then_sum.kt", file: #filePath),
            expectedOutput: "10\n",
            moduleName: "KUU2331StringMapSum",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

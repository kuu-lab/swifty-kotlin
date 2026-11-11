import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testSortedOrder(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("stdlib_is_sorted.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "StdlibSortedOrder",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testListReduceAccumulatorContract(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("list_reduce_accumulator.kt", file: #filePath),
            expectedOutput: "6\n6\n6\n6\n6\n3\n7\n6\nuser\n42\nEmpty collection can't be reduced.\n",
            moduleName: "KUU2065ListReduce",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testStringEncodingDefaultIndicesAndBounds(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("string_encoding_default_indices.kt", file: #filePath),
            expectedOutput: "FGHI\ncalls:1\nFGHI\nBCDE\nDEFG\nBCDEFGHI\n0\n0\n0\né中Z\nAé中\nZ\nA😀\n"
                + "negative-start\npast-end\ninvalid-end\nreversed-range\nnegative-end\n"
                + "outside-before-reversed\nnegative-before-reversed\n",
            moduleName: "KUU1766StringEncodingDefaults",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

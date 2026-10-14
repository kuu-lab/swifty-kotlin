import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testCharsetForNameFirstAccess(allowDefaultStdlibLibrary: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("charset_forname_first.kt", file: #filePath),
            expectedOutput: "UTF-8\nISO-8859-1\né\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimization == 2 ? .O2 : .O0,
            expectedStderr: ""
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func testDefaultCharsetMinimalReproducer(allowDefaultStdlibLibrary: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("charset_default.kt", file: #filePath),
            expectedOutput: "UTF-8\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimization == 2 ? .O2 : .O0,
            expectedStderr: ""
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func testDefaultCharsetRoundtrip(allowDefaultStdlibLibrary: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("charset_default_roundtrip.kt", file: #filePath),
            expectedOutput: "UTF-8\ntrue\ntrue\ntrue\ntrue\nUTF-8\n"
                + "[104, -61, -87, -26, -105, -91, -26, -100, -84, -16, -97, -104, -128]\ntrue\n"
                + String(repeating: "hé日本😀\n", count: 4) + "true\nhé日本😀\n"
                + "ISO-8859-1\n[-23]\né\nUTF-16BE\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimization == 2 ? .O2 : .O0,
            expectedStderr: ""
        )
    }
}

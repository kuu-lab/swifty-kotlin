import Testing

extension BundledStdlibExecutionTests {
    // KUU-2040: run the JVM-verified contract through both stdlib routes and levels.
    @Test(arguments: [true, false], [0, 2])
    func testStringBuilderAppendCodePoint(
        allowDefaultStdlibLibrary: Bool,
        optimizationLevel: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("string_builder_append_code_point.kt", file: #filePath),
            expectedOutput: """
                0:2:true:112,0:112,0
                1:2:true:112,1:112,1
                65:2:true:112,65:112,65
                233:2:true:112,233:112,233
                55295:2:true:112,55295:112,55295
                55296:2:true:112,55296:112,55296
                56319:2:true:112,56319:112,56319
                56320:2:true:112,56320:112,56320
                57343:2:true:112,57343:112,57343
                57344:2:true:112,57344:112,57344
                65535:2:true:112,65535:112,65535
                65536:3:true:112,55296,56320:112,55296,56320
                128512:3:true:112,55357,56832:112,55357,56832
                1114111:3:true:112,56319,57343:112,56319,57343
                invalid:-1:unchanged:9:true
                invalid:1114112:unchanged:9:true
                invalid:-2147483648:unchanged:9:true
                invalid:2147483647:unchanged:9:true
                decimal:65A
                chained:A😀:3
                implicit:😀
                xenocom:65,55357,56832,160:65,55357,56832,32
                control:65
                cleared:0:0
                """ + "\n",
            moduleName: "KUU2040AppendCodePoint",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimizationLevel == 0 ? .O0 : .O2
        )
    }
}

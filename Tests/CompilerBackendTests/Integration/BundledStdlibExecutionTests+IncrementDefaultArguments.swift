import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func extensionPrefixIncrementWithDefaultArgument(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3600_extension_prefix_inc_default_arg.kt", file: #filePath),
            expectedOutput: """
            OK
            prefix statement: 12, defaults=1
            prefix value: 14, current=14, defaults=2
            postfix value: 14, current=16, defaults=3
            prefix decrement: 14, current=14, defaults=4
            postfix decrement: 14, current=12, defaults=5

            """,
            moduleName: "KUU3600PrefixIncrementDefaultArgument",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false], [0, 2])
    func booleanNotIntrinsicCallableReference(
        allowDefaultStdlibLibrary: Bool,
        optimizationLevel: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("boolean_not_callable_reference.kt", file: #filePath),
            expectedOutput: "OK\nfalse\ntrue\nfalse\nfalse\n",
            moduleName: "KUU2341BooleanNotCallableReference",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimizationLevel == 0 ? .O0 : .O2
        )
    }
}

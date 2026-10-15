import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func sameOverloadedFunctionReferenceComparesEqual(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("callable_reference_equality_overload.kt", file: #filePath),
            expectedOutput: "true\ntrue\nfalse\n",
            moduleName: "KUU2101CallableReferenceEquality",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

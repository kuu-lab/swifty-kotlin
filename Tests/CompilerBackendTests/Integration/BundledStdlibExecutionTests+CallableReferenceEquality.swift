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

    @Test(arguments: [true, false])
    func contextualCallableReferencesCompareCapturedContextValues(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3309_contextual_callable_reference_equality.kt", file: #filePath),
            expectedOutput: "true\ntrue\nfalse\nA1\ntrue\ntrue\nfalse\nA1\n",
            moduleName: "KUU3309ContextualCallableReferenceEquality",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

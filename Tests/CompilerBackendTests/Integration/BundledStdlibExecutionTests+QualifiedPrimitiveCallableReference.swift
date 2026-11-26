import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false], [0, 2])
    func qualifiedPrimitiveCallableReference(
        allowDefaultStdlibLibrary: Bool,
        optimizationLevel: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("qualified_primitive_callable_reference.kt", file: #filePath),
            expectedOutput: "OK\nor\n6\nfalse\n6\n",
            moduleName: "KUU4137QualifiedPrimitiveCallableReference",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimizationLevel == 0 ? .O0 : .O2
        )
    }
}

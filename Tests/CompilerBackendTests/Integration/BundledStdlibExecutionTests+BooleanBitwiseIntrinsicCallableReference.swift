import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false], [0, 2])
    func booleanBitwiseIntrinsicCallableReference(
        allowDefaultStdlibLibrary: Bool,
        optimizationLevel: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("boolean_bitwise_member_callable_reference.kt", file: #filePath),
            expectedOutput: "OK\nand\nor\nxor\nfalse\ntrue\nfalse\nfalse\ntrue\nfalse\n",
            moduleName: "KUU4092BooleanBitwiseCallableReference",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimizationLevel == 0 ? .O0 : .O2
        )
    }
}

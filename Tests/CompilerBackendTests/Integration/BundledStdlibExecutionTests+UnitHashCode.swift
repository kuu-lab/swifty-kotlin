import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testUnitHashCodeUsesStableNonzeroIdentity(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu3466_unit_hashcode.kt", file: #filePath),
            expectedOutput: String(repeating: "true\n", count: 5),
            moduleName: "KUU3466UnitHashCode",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}

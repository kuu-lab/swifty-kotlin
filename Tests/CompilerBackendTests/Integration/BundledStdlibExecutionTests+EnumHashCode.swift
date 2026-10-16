import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    // KUU-2413: enum hashCode keeps singleton identity across direct and
    // Any-erased receivers in both bundled-source and imported-stdlib paths.
    @Test(arguments: [false, true], [0, 2])
    func testEnumEntryHashCodeMatchesJvmBehavior(
        allowDefaultStdlibLibrary: Bool,
        optimizationLevel: Int
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlin(
            try diffCaseSource("enum_entry_hashcode.kt", file: #filePath),
            expectedOutput: "OK\nstable=true\nnotOrdinal=true\nerased=true\nplainStable=true\nplainDistinct=true\nexplicit=12345\n",
            moduleName: "KUU2413EnumEntryHashCode",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimizationLevel == 0 ? .O0 : .O2
        )
    }
}

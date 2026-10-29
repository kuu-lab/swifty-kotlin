@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    // The fixture is pinned to JetBrains Kotlin commit 679366a83f99851b42f64795f10ed803ff011c73.
    // Its body SHA-256 is 99fd3754c612291e71b863932a4e85c464bb0b221f5fe55c4e05abffe3cd902b;
    // the checked-in main wrapper produces the issue's measured-copy SHA-256 13a1a9087d4fb513279f3507acd170a2951c0d05c7d173da489461515d3ac78c.
    // Source-injected O2 currently hits the baseline invalid-IR issue tracked by KUU-2399.
    @Test(arguments: [0])
    func topLevelCustomSetterMatchesKt4152WithStdlibSource(optimization: Int) throws {
        try runTopLevelCustomSetterRegression(
            sourceFile: "kt4152_top_level_property_increment.kt",
            expectedFile: "kt4152_top_level_property_increment.expected",
            moduleName: "KUU2374Kt4152Source",
            allowDefaultStdlibLibrary: false,
            optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func topLevelCustomSetterMatchesKt4152WithFreshStdlibLibrary(optimization: Int) throws {
        try runTopLevelCustomSetterRegression(
            sourceFile: "kt4152_top_level_property_increment.kt",
            expectedFile: "kt4152_top_level_property_increment.expected",
            moduleName: "KUU2374Kt4152Library",
            allowDefaultStdlibLibrary: true,
            optimization: optimization
        )
    }

    @Test(arguments: [0])
    func topLevelCustomSetterIncDecExpressionsMatchReferenceWithStdlibSource(optimization: Int) throws {
        try runTopLevelCustomSetterRegression(
            sourceFile: "top_level_property_custom_setter_incdec.kt",
            expectedFile: "top_level_property_custom_setter_incdec.expected",
            moduleName: "KUU2374TopLevelSetterIncDecSource",
            allowDefaultStdlibLibrary: false,
            optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func topLevelCustomSetterIncDecExpressionsMatchReferenceWithFreshStdlibLibrary(optimization: Int) throws {
        try runTopLevelCustomSetterRegression(
            sourceFile: "top_level_property_custom_setter_incdec.kt",
            expectedFile: "top_level_property_custom_setter_incdec.expected",
            moduleName: "KUU2374TopLevelSetterIncDecLibrary",
            allowDefaultStdlibLibrary: true,
            optimization: optimization
        )
    }

    private func runTopLevelCustomSetterRegression(
        sourceFile: String,
        expectedFile: String,
        moduleName: String,
        allowDefaultStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource(sourceFile, file: #filePath),
            expectedOutput: try diffCaseSource(expectedFile, file: #filePath),
            moduleName: moduleName,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}

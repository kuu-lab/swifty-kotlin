@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
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

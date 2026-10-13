@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct LocalOperatorDelegateExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func localOperatorWinsOverOuterExtension(useArtifact: Bool, optimization: Int) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlinSources(
            [diffCaseSource("local_operator_delegate_priority.kt")],
            expectedOutput: "2\n", moduleName: "KUU2023LocalOperatorPriority",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "", requireNoCompilerDiagnostics: true
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func localOnlyAndConventionControls(useArtifact: Bool, optimization: Int) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlinSources(
            [diffCaseSource("local_operator_delegate_controls.kt")],
            expectedOutput: "3\n1\n4\n1\n9\n8\n13\n14\n", moduleName: "KUU2023LocalOperatorControls",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "", requireNoCompilerDiagnostics: true
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func capturedOperatorsAcrossDirectAndNestedAccesses(useArtifact: Bool, optimization: Int) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlinSources(
            [diffCaseSource("local_operator_delegate_captures.kt")],
            expectedOutput: "40\n50\n52\n52\n52\n40\n40\n1\n2\n2\n", moduleName: "KUU2023LocalOperatorCaptures",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "", requireNoCompilerDiagnostics: true
        )
    }
}

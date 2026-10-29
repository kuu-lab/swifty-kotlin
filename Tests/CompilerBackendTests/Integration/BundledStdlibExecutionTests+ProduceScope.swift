@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func produceBuilderSurvivesInapplicableSameName(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("produce_inapplicable_scope_extension.kt", file: #filePath)
        try compileAndRunKotlin(
            source, expectedOutput: "1\n", moduleName: "ProduceInapplicableScopeExtension",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)), expectedStderr: ""
        )
    }

    @Test
    func nearerUserProduceRemainsSelected() throws {
        let source = try diffCaseSource("produce_nearer_user_extension.kt", file: #filePath)
        try compileAndRunKotlin(
            source, expectedOutput: "13\n", moduleName: "ProduceNearerUserExtension",
            allowDefaultStdlibLibrary: false, expectedStderr: ""
        )
    }
}

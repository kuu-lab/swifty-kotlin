@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func erasedGenericValueDestinations(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("erased_generic_value_boundaries.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: """
            marker
            direct-any:true
            direct-arg:true
            direct-parent:true
            direct-parent-arg:true
            direct-generic:true
            wrong-string:CCE
            nonnull-any:true
            typed-int:CCE
            return-any:true
            return-block:true
            return-parent:true
            return-target:CCE
            assign-local:true
            assign-property:true
            generic-write:ok
            generic-read:CCE
            branch-any:CCE
            branch-block:CCE
            lambda-any:true
            lambda-branch:CCE
            lambda-inferred:CCE
            lambda-generic:CCE
            lambda-typed:CCE
            null-any:true
            null-int:true
            valid-int:42

            """,
            moduleName: "ErasedGenericValueDestinations",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

}

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

    @Test(arguments: [false, true], [0, 2])
    func erasedGenericClaimConsumers(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("unchecked_cast_claim_consumers.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: """
            ne:true
            eq-null:false
            id-eq-self:false
            id-ne-null:true
            eq-other:false
            is-claimed:true
            is-ci:true
            is-c:true
            is-i1:true
            not-is-claimed:false
            is-claimed-nullable:false
            is-c-nullable:true
            null-is-nullable:true
            as:CCE
            safe-as-claimed:true
            safe-as-c:true
            bang:CI1I2
            template:CI1I2
            thrown-re
            when:CCE
            typed:CCE
            typed-arg:true
            any-arg:true
            raw-is-ci:true
            raw-ne:true
            stmt-ok

            """,
            moduleName: "ErasedGenericClaimConsumers",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    /// KUU-4393: a statement-position call records a Unit consumer so the
    /// erased result is popped without a claim checkcast. A platform-typed
    /// expression bound must not resurrect that checkcast — `ConcurrentMap`'s
    /// `putIfAbsent`/`replace` return a flexible `V!`, which kept `bound`
    /// non-Unit and emitted a bogus `kk_op_cast` to Unit that panicked on
    /// any non-null discarded result.
    @Test(arguments: [false, true], [0, 2])
    func erasedGenericDiscardedStatementResult(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource(
            "kuu_4393_concurrent_map_discarded_erased_result.kt",
            file: #filePath
        )
        try compileAndRunKotlin(
            source,
            expectedOutput: """
            9
            3
            9
            1

            """,
            moduleName: "ErasedGenericDiscardedStatementResult",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

}

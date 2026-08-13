#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct OverloadResolutionByLambdaReturnTypeTests {

    @Test func testOverloadResolutionByLambdaReturnTypeSema() throws {
        let sources: [String] = [
            // testUnannotatedLambdaReturnTypeOverloadsRemainAmbiguous
            """
            package sample0
                    fun foo(block: () -> Int): Int = 1
                    fun foo(block: () -> String): String = "s"

                    fun test(): Int = foo { 42 }

            """,

            // testAnnotatedLambdaReturnTypeOverloadSelectsMatchingTopLevelOverload
            """
            package sample1
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun foo(block: () -> Int): Int = 1
                    fun foo(block: () -> String): String = "s"

                    fun test(): Int = foo { 42 }

            """,

            // testAnnotatedLambdaReturnTypeOverloadCanSelectNonAnnotatedCandidate
            """
            package sample2
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun foo(block: () -> Int): Int = 1
                    fun foo(block: () -> String): String = "s"

                    fun test(): String = foo { "x" }

            """,

            // testDifferentLambdaInputShapesRemainAmbiguous
            """
            package sample3
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun foo(block: (Int) -> Int): Int = 1
                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun foo(block: (String) -> Int): String = "s"

                    fun test() = foo { 42 }

            """,

            // testMultipleLambdaArgumentsRemainAmbiguous
            """
            package sample4
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun foo(a: () -> Int, b: () -> String): Int = 1
                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun foo(a: () -> Int, b: () -> Int): String = "s"

                    fun test() = foo({ 42 }, { "x" })

            """,

            // testImplicitItParameterOverloadAmbiguityIsDetected
            """
            package sample5
                    fun process(block: (Int) -> String) = block(1)
                    fun process(block: (String) -> Int) = block("a")

                    val result = process { it }

            """,

            // testExplicitlyTypedLambdaParameterResolvesDespiteDifferingCandidateShapes
            """
            package sample6
                    fun process(block: (Int) -> String) = block(1)
                    fun process(block: (String) -> Int) = block("a")

                    val result: String = process { x: Int -> x.toString() }

            """,

            // testCallableReferenceStillResolvesNormally
            """
            package sample7
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    fun provideInt(): Int = 1

                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun foo(block: () -> Int): Int = 1
                    fun foo(block: () -> String): String = "s"

                    fun test(): Int = foo(::provideInt)

            """,

            // testMemberCallRefinesByLambdaReturnType
            """
            package sample8
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    class Host {
                        @OptIn(ExperimentalTypeInference::class)
                        @OverloadResolutionByLambdaReturnType
                        fun foo(block: () -> Int): Int = 1

                        fun foo(block: () -> String): String = "s"
                    }

                    fun test(host: Host): Int = host.foo { 42 }

            """,

            // testSafeMemberCallRefinesByLambdaReturnType
            """
            package sample9
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    class Host {
                        @OptIn(ExperimentalTypeInference::class)
                        @OverloadResolutionByLambdaReturnType
                        fun foo(block: () -> Int): Int = 1

                        fun foo(block: () -> String): String = "s"
                    }

                    fun test(host: Host?): Int? = host?.foo { 42 }

            """,

            // testExtensionCallRefinesByLambdaReturnType
            """
            package sample10
                    import kotlin.OptIn
                    import kotlin.OverloadResolutionByLambdaReturnType
                    import kotlin.experimental.ExperimentalTypeInference

                    class Host

                    @OptIn(ExperimentalTypeInference::class)
                    @OverloadResolutionByLambdaReturnType
                    fun Host.foo(block: () -> Int): Int = 1

                    fun Host.foo(block: () -> String): String = "s"

                    fun test(host: Host): Int = host.foo { 42 }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testUnannotatedLambdaReturnTypeOverloadsRemainAmbiguous
            do {
                let samplePath = paths[0]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    sampleDiags.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1,
                    "Expected ambiguous overload resolution without annotation, got: \(sampleDiags)"
                )
            }
            // testAnnotatedLambdaReturnTypeOverloadSelectsMatchingTopLevelOverload
            do {
                let samplePath = paths[1]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected annotated overload to resolve cleanly, got: \(sampleDiags)")
            }
            // testAnnotatedLambdaReturnTypeOverloadCanSelectNonAnnotatedCandidate
            do {
                let samplePath = paths[2]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected refinement to keep the matching non-annotated overload, got: \(sampleDiags)")
            }
            // testDifferentLambdaInputShapesRemainAmbiguous
            do {
                let samplePath = paths[3]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    sampleDiags.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1,
                    "Expected ambiguity when lambda parameter shapes differ, got: \(sampleDiags)"
                )
            }
            // testMultipleLambdaArgumentsRemainAmbiguous
            do {
                let samplePath = paths[4]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    sampleDiags.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1,
                    "Expected ambiguity when multiple lambda return types participate, got: \(sampleDiags)"
                )
            }
            // testImplicitItParameterOverloadAmbiguityIsDetected
            do {
                let samplePath = paths[5]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    sampleDiags.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1,
                    "Expected a clean ambiguity diagnostic (DEBT-SEMA-004), got: \(sampleDiags)"
                )
                #expect(
                    sampleDiags.filter { $0.code == "KSWIFTK-SEMA-0022" }.count == 1,
                    "Expected the unresolved 'it' reference cascade, got: \(sampleDiags)"
                )
                #expect(
                    sampleDiags.filter { $0.code == "KSWIFTK-SEMA-0002" }.isEmpty,
                    "Expected no additional no-viable-overload cascade once ambiguity is detected directly, got: \(sampleDiags)"
                )
            }
            // testExplicitlyTypedLambdaParameterResolvesDespiteDifferingCandidateShapes
            do {
                let samplePath = paths[6]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(
                    sampleDiags.isEmpty,
                    "Expected an explicitly-typed lambda parameter to disambiguate normally, got: \(sampleDiags)"
                )
            }
            // testCallableReferenceStillResolvesNormally
            do {
                let samplePath = paths[7]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected callable reference overload resolution to keep working, got: \(sampleDiags)")
            }
            // testMemberCallRefinesByLambdaReturnType
            do {
                let samplePath = paths[8]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected member-call refinement to resolve cleanly, got: \(sampleDiags)")
            }
            // testSafeMemberCallRefinesByLambdaReturnType
            do {
                let samplePath = paths[9]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected safe member-call refinement to resolve cleanly, got: \(sampleDiags)")
            }
            // testExtensionCallRefinesByLambdaReturnType
            do {
                let samplePath = paths[10]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected extension-call refinement to resolve cleanly, got: \(sampleDiags)")
            }

        }
    }



    // Fixed (DEBT-SEMA-004, migrated from Scripts/diff_cases/error_type_inference.kt / DEBT-DIFF-006):
    // Neither candidate is annotated with @OverloadResolutionByLambdaReturnType, and the lambda body
    // only reads the implicit `it` parameter, so its shape can't be fixed before an overload is picked.
    // kotlinc 2.4.0 rejects this with:
    //   error: overload resolution ambiguity between candidates:
    //   fun process(block: (Int) -> String): String
    //   fun process(block: (String) -> Int): Int
    //   error: unresolved reference 'it'.
    // kswiftc now detects the ambiguity directly (KSWIFTK-SEMA-0003) instead of only cascading a
    // "no viable overload" from the unresolved `it` reference. The unresolved-`it` diagnostic itself
    // still fires -- the lambda body is checked before an overload can be chosen, exactly like
    // kotlinc's own second error line above -- but resolution stops there rather than additionally
    // reporting "no viable overload" once every candidate's arity mismatches the resulting `() -> _`
    // fallback type.




    // Companion case for DEBT-SEMA-004: an explicitly-typed lambda parameter carries its own
    // type regardless of what the surviving candidates expect, so there is no implicit-`it`
    // ambiguity to detect -- normal argument-type matching picks the one candidate whose
    // parameter type accepts it, exactly like kotlinc.




}
#endif

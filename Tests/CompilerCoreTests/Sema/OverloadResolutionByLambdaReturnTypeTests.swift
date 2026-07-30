#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct OverloadResolutionByLambdaReturnTypeTests {
    @Test func testUnannotatedLambdaReturnTypeOverloadsRemainAmbiguous() {
        let source = """
        fun foo(block: () -> Int): Int = 1
        fun foo(block: () -> String): String = "s"

        fun test(): Int = foo { 42 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            diagnostics(withCode: "KSWIFTK-SEMA-0003", in: ctx).count == 1,
            "Expected ambiguous overload resolution without annotation, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testAnnotatedLambdaReturnTypeOverloadSelectsMatchingTopLevelOverload() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = 1
        fun foo(block: () -> String): String = "s"

        fun test(): Int = foo { 42 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected annotated overload to resolve cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testAnnotatedLambdaReturnTypeOverloadCanSelectNonAnnotatedCandidate() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = 1
        fun foo(block: () -> String): String = "s"

        fun test(): String = foo { "x" }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected refinement to keep the matching non-annotated overload, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testDifferentLambdaInputShapesRemainAmbiguous() {
        let source = """
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
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            diagnostics(withCode: "KSWIFTK-SEMA-0003", in: ctx).count == 1,
            "Expected ambiguity when lambda parameter shapes differ, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testMultipleLambdaArgumentsRemainAmbiguous() {
        let source = """
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
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            diagnostics(withCode: "KSWIFTK-SEMA-0003", in: ctx).count == 1,
            "Expected ambiguity when multiple lambda return types participate, got: \(ctx.diagnostics.diagnostics)"
        )
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
    @Test func testImplicitItParameterOverloadAmbiguityIsDetected() {
        let source = """
        fun process(block: (Int) -> String) = block(1)
        fun process(block: (String) -> Int) = block("a")

        val result = process { it }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            diagnostics(withCode: "KSWIFTK-SEMA-0003", in: ctx).count == 1,
            "Expected a clean ambiguity diagnostic (DEBT-SEMA-004), got: \(ctx.diagnostics.diagnostics)"
        )
        #expect(
            diagnostics(withCode: "KSWIFTK-SEMA-0022", in: ctx).count == 1,
            "Expected the unresolved 'it' reference cascade, got: \(ctx.diagnostics.diagnostics)"
        )
        #expect(
            diagnostics(withCode: "KSWIFTK-SEMA-0002", in: ctx).isEmpty,
            "Expected no additional no-viable-overload cascade once ambiguity is detected directly, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    // Companion case for DEBT-SEMA-004: an explicitly-typed lambda parameter carries its own
    // type regardless of what the surviving candidates expect, so there is no implicit-`it`
    // ambiguity to detect -- normal argument-type matching picks the one candidate whose
    // parameter type accepts it, exactly like kotlinc.
    @Test func testExplicitlyTypedLambdaParameterResolvesDespiteDifferingCandidateShapes() {
        let source = """
        fun process(block: (Int) -> String) = block(1)
        fun process(block: (String) -> Int) = block("a")

        val result: String = process { x: Int -> x.toString() }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "Expected an explicitly-typed lambda parameter to disambiguate normally, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testCallableReferenceStillResolvesNormally() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        fun provideInt(): Int = 1

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = 1
        fun foo(block: () -> String): String = "s"

        fun test(): Int = foo(::provideInt)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected callable reference overload resolution to keep working, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testMemberCallRefinesByLambdaReturnType() {
        let source = """
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
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected member-call refinement to resolve cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testSafeMemberCallRefinesByLambdaReturnType() {
        let source = """
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
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected safe member-call refinement to resolve cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExtensionCallRefinesByLambdaReturnType() {
        let source = """
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

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected extension-call refinement to resolve cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted per test.
        }
        return ctx
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }
}
#endif

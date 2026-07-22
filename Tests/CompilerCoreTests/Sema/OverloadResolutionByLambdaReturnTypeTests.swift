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

    // KNOWN GAP (DEBT-SEMA-001, migrated from Scripts/diff_cases/error_type_inference.kt / DEBT-DIFF-006):
    // Neither candidate is annotated with @OverloadResolutionByLambdaReturnType, and the lambda body
    // only reads the implicit `it` parameter, so its shape can't be fixed before an overload is picked.
    // kotlinc 2.4.0 rejects this:
    //   error: overload resolution ambiguity between candidates:
    //   fun process(block: (Int) -> String): String
    //   fun process(block: (String) -> Int): Int
    //   error: unresolved reference 'it'.
    // kswiftc now reports an error for the unresolved call, though it still does not emit the exact
    // KSWIFTK-SEMA-0003 ambiguity diagnostic. This test will fail once DEBT-SEMA-001 is fully fixed
    // and the call resolves cleanly (or emits only the expected ambiguity diagnostic).
    @Test func testImplicitItParameterOverloadAmbiguityIsNotYetDetected() {
        let source = """
        fun process(block: (Int) -> String) = block(1)
        fun process(block: (String) -> Int) = block("a")

        val result = process { it }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(!ctx.diagnostics.diagnostics.isEmpty, "Expected unresolved overload diagnostics, got: \(ctx.diagnostics.diagnostics)")
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

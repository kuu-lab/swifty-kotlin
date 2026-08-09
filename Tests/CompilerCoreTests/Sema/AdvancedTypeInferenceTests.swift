#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AdvancedTypeInferenceTests {
    @Test func testExperimentalTypeInference() throws {
        let sources: [String] = [
            // testExperimentalTypeInferenceInfersCustomBuilderElementTypeWithoutExpectedType
            """
            package sample0
            import kotlin.experimental.ExperimentalTypeInference

            @ExperimentalTypeInference
            fun <T> collect(builderAction: MutableList<T>.() -> Unit): List<T> = TODO()

            fun demo(): Int {
                val xs = collect {
                    add(1)
                    add(2)
                }
                return xs[0]
            }
            """,

            // testExperimentalTypeInferenceAnnotationIsAvailableWithoutCompilerFlags
            """
            package sample1
            import kotlin.experimental.ExperimentalTypeInference

            @ExperimentalTypeInference
            fun <T> annotatedCollect(builderAction: MutableList<T>.() -> Unit): List<T> = TODO()

            fun demo() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                frontendFlags: [
                    "new-inference",
                    "unrestricted-builder-inference",
                    "ProperTypeInferenceConstraintsProcessing",
                ]
            )
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

            #expect(
                !ctx.diagnostics.hasError,
                "Expected custom builder inference to succeed, got: \(diagnostics)"
            )

            let sample1Diags = diagnosticsForPath(paths[1], in: ctx)
            #expect(
                !sample1Diags.contains(where: { $0.severity == .error }),
                "Expected annotation-driven builder inference to succeed, got: \(sample1Diags)"
            )
        }
    }
}
#endif

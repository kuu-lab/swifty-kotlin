#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AdvancedTypeInferenceTests {
    @Test func testExperimentalTypeInferenceInfersCustomBuilderElementTypeWithoutExpectedType() throws {
        let source = """
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
        """

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt")
            .path
        let ctx = makeCompilationContext(
            inputs: [path],
            frontendFlags: [
                "new-inference",
                "unrestricted-builder-inference",
                "ProperTypeInferenceConstraintsProcessing",
            ]
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))

        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected custom builder inference to succeed, got: \(diagnostics)"
        )
    }

    @Test func testExperimentalTypeInferenceAnnotationIsAvailableWithoutCompilerFlags() throws {
        let source = """
        import kotlin.experimental.ExperimentalTypeInference

        @ExperimentalTypeInference
        fun <T> annotatedCollect(builderAction: MutableList<T>.() -> Unit): List<T> = TODO()

        fun demo() {}
        """

        let ctx = makeContextFromSource(source)

        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected annotation-driven builder inference to succeed, got: \(diagnostics)"
        )
    }
}
#endif

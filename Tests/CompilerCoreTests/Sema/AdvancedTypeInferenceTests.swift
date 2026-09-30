#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AdvancedTypeInferenceTests {
    @Test func testGenericCollectionReceiverLambdaInfersWithoutAnnotation() throws {
        let source = """
        fun <T> collect(builderAction: MutableList<T>.() -> Unit): List<T> = buildList<T>(builderAction)

        fun demo(): Int {
            val xs = collect {
                add(1)
                add(2)
            }
            return xs[0]
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
        #expect(!ctx.diagnostics.hasError, "Expected collect's receiver lambda to infer T from add(), got: \(diagnostics)")
    }

    @Test func testSequenceBuilderYieldAllListChoosesIterableOverload() throws {
        let source = """
        fun values(): List<Int> = sequence {
            yieldAll(listOf(1, 2))
        }.toList()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
        #expect(!ctx.diagnostics.hasError, "Expected yieldAll(List<Int>) to select Iterable<T>, got: \(diagnostics)")
    }

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

    @Test func testBuildListWithNamedCapacityArgumentInfersElementType() throws {
        let source = """
        fun demo(): List<Int> {
            return buildList(capacity = 10) {
                add(1)
                add(2)
            }
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
            "Expected buildList(capacity = ...) with named argument to infer element type, got: \(diagnostics)"
        )
    }

    @Test func testBuildListWithNonLambdaArgumentReportsNoViableOverload() throws {
        let source = """
        fun demo() {
            buildList(1)
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
            ctx.diagnostics.hasError,
            "Expected buildList(1) to report a no-viable-overload error, got: \(diagnostics)"
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

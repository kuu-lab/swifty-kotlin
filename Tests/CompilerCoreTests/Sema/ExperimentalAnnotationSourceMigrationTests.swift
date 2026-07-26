#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-668: `kotlin.experimental.ExperimentalTypeInference` and
/// `kotlin.experimental.ExperimentalNativeApi` are now declared by bundled
/// Kotlin source instead of synthetic stubs. These tests lock in that the
/// markers still resolve and that `ExperimentalNativeApi` keeps its
/// `@RequiresOptIn` opt-in behavior.
@Suite
struct ExperimentalAnnotationSourceMigrationTests {
    @Test func testExperimentalTypeInferenceResolvesAsTypeViaImport() throws {
        let source = """
        import kotlin.experimental.ExperimentalTypeInference

        fun marker(x: ExperimentalTypeInference?): Int = 0
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected ExperimentalTypeInference to resolve as a type via import, got: \(diagnostics)"
        )
    }

    @Test func testExperimentalTypeInferenceResolvesAsTypeViaFQN() throws {
        let source = """
        fun marker(x: kotlin.experimental.ExperimentalTypeInference?): Int = 0
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected ExperimentalTypeInference to resolve as a type via FQN, got: \(diagnostics)"
        )
    }

    @Test func testExperimentalNativeApiResolvesAsType() throws {
        let source = """
        import kotlin.experimental.ExperimentalNativeApi

        fun marker(x: ExperimentalNativeApi?): Int = 0
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected ExperimentalNativeApi to resolve as a type via import, got: \(diagnostics)"
        )
    }

    @Test func testExperimentalNativeApiResolvesFromBundledSource() throws {
        let source = """
        @kotlin.experimental.ExperimentalNativeApi
        fun experimentalApi(): Int = 42

        fun demo() {}
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.hasError,
            "Expected marking an API with ExperimentalNativeApi to succeed, got: \(diagnostics)"
        )
    }

    @Test func testExperimentalNativeApiRequiresOptInWhenUsed() throws {
        let source = """
        @kotlin.experimental.ExperimentalNativeApi
        fun experimentalApi(): Int = 42

        fun useIt(): Int = experimentalApi()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" },
            "Expected an opt-in error when using ExperimentalNativeApi without opt-in"
        )
    }

    @Test func testExperimentalNativeApiOptInSuppressesError() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        @kotlin.experimental.ExperimentalNativeApi
        fun experimentalApi(): Int = 42

        fun useIt(): Int = experimentalApi()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }

        #expect(
            !ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" },
            "Expected opt-in to suppress the ExperimentalNativeApi error, got: \(diagnostics)"
        )
    }
}
#endif

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

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testExperimentalTypeInferenceResolvesAsTypeViaImport
            """
            package sample0

                    import kotlin.experimental.ExperimentalTypeInference

                    fun marker(x: ExperimentalTypeInference?): Int = 0

            """,
            // testExperimentalTypeInferenceResolvesAsTypeViaFQN
            """
            package sample1

                    fun marker(x: kotlin.experimental.ExperimentalTypeInference?): Int = 0

            """,
            // testExperimentalNativeApiResolvesAsType
            """
            package sample2

                    import kotlin.experimental.ExperimentalNativeApi

                    fun marker(x: ExperimentalNativeApi?): Int = 0

            """,
            // testExperimentalNativeApiResolvesFromBundledSource
            """
            package sample3

                    @kotlin.experimental.ExperimentalNativeApi
                    fun experimentalApi(): Int = 42

                    fun demo() {}

            """,
            // testExperimentalNativeApiRequiresOptInWhenUsed
            """
            package sample4

                    @kotlin.experimental.ExperimentalNativeApi
                    fun experimentalApi(): Int = 42

                    fun useIt(): Int = experimentalApi()

            """,
            // testExperimentalNativeApiOptInSuppressesError
            """
            package sample5

                    @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

                    @kotlin.experimental.ExperimentalNativeApi
                    fun experimentalApi(): Int = 42

                    fun useIt(): Int = experimentalApi()

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            _ = try #require(ctx.sema)


            // === testExperimentalTypeInferenceResolvesAsTypeViaImport ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let diagnostics = sample0Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample0Diagnostics.contains { $0.severity == .error },
                    "Expected ExperimentalTypeInference to resolve as a type via import, got: \(diagnostics)"
                )

            }

            // === testExperimentalTypeInferenceResolvesAsTypeViaFQN ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnostics = sample1Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "Expected ExperimentalTypeInference to resolve as a type via FQN, got: \(diagnostics)"
                )

            }

            // === testExperimentalNativeApiResolvesAsType ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let diagnostics = sample2Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample2Diagnostics.contains { $0.severity == .error },
                    "Expected ExperimentalNativeApi to resolve as a type via import, got: \(diagnostics)"
                )

            }

            // === testExperimentalNativeApiResolvesFromBundledSource ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let diagnostics = sample3Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample3Diagnostics.contains { $0.severity == .error },
                    "Expected marking an API with ExperimentalNativeApi to succeed, got: \(diagnostics)"
                )

            }

            // === testExperimentalNativeApiRequiresOptInWhenUsed ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(
                    sample4Diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" },
                    "Expected an opt-in error when using ExperimentalNativeApi without opt-in"
                )

            }

            // === testExperimentalNativeApiOptInSuppressesError ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let diagnostics = sample5Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample5Diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" },
                    "Expected opt-in to suppress the ExperimentalNativeApi error, got: \(diagnostics)"
                )

            }

        }
    }

}

#endif

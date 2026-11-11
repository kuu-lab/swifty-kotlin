@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [false, true])
    func testCollectionEqualityAcrossSourceAndFreshLibrary(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repoRoot.appendingPathComponent("Scripts/diff_cases/collection_equality.kt")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: output) }

        let context = try runCodegenPipeline(
            inputPath: fixture.path,
            moduleName: "CollectionEquality",
            outputPath: output,
            allowDefaultStdlibLibrary: false,
            stdlibLibraryPath: artifactPath,
            includeStdlib: !useArtifact,
            prepareTestStdlibCache: false
        )
        try assertNoDiagnosticErrors(context)
        try LinkPhase().run(context)
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "Unexpected stderr: \(result.stderr)")
        #expect(result.stdout == "OK\n")
    }

    @Test(arguments: [false, true])
    func testCollectionEqualityRequiresOptIn(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        fun requiresStdlibOptIn() {
            listOf(1).allEqual()
            sequenceOf(1).allEqualBy { it }
            arrayOf(1).allDistinct()
            intArrayOf(1).allDistinctBy { it }
        }

        @OptIn(ExperimentalStdlibApi::class)
        fun requiresUnsignedOptIn(values: UIntArray) {
            values.allDistinct()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = CompilerTestSupport.makeCompilationContext(
                inputs: [path],
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            do {
                try runSema(context)
            } catch {
                // Inspect errors at the call sites.
            }

            let diagnostics = context.diagnostics.diagnostics.filter {
                guard let range = $0.primaryRange else { return false }
                return isUserSourceRange(range, in: context)
            }
            let errors = diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 4)
            #expect(errors.allSatisfy {
                $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("ExperimentalStdlibApi")
            })
            #expect(diagnostics.contains {
                $0.severity == .warning && $0.code == "KSWIFTK-SEMA-OPT-IN"
                    && $0.message.contains("ExperimentalUnsignedTypes")
            })
        }
    }
}

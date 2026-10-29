@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2744: DebugProbes must observe launched coroutines through the shared stdlib artifact.
    @Test
    func testDebugProbesTrackCoroutineStateContextAndCreationStack() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.debug.*

        fun main() = runBlocking {
            DebugProbes.install()
            DebugProbes.enableCreationStackTraces = true
            DebugProbes.sanitizeStackTraces = false

            val job = launch { delay(60000) }
            yield()

            val info = DebugProbes.dumpCoroutinesInfo().firstOrNull { it.job === job }
            println("installed:${DebugProbes.isInstalled}")
            println("tracked:${info != null}")
            println("suspended:${info?.state == State.SUSPENDED}")
            println("has-job-context:${info?.context?.get(Job) === job}")
            println("creation-stack:${info?.creationStackTrace?.isNotEmpty()}")
            DebugProbes.dumpCoroutines()

            job.cancel()
            val cancelledInfo = DebugProbes.dumpCoroutinesInfo().firstOrNull { it.job === job }
            println("cancelled:${cancelledInfo?.state == State.CANCELLED}")
            job.join()
            println("removed:${DebugProbes.dumpCoroutinesInfo().isEmpty()}")
            DebugProbes.uninstall()

            println("with-result:${DebugProbes.withDebugProbes { 123 }}")
            println("installed-after:${DebugProbes.isInstalled}")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let context = makeCompilationContext(
                inputs: [userPath],
                moduleName: "DebugProbesTracking",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(context)
            try #require(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
                    == "installed:true\ntracked:true\nsuspended:true\nhas-job-context:true\ncreation-stack:true\ncancelled:true\nremoved:true\nwith-result:123\ninstalled-after:false\n"
            )
        }
    }
}

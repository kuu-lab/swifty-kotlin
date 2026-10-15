@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {
    /// KUU-2224: local class modality must allow anonymous-object inheritance.
    @Test(arguments: [false, true], [0, 2])
    func testAnonymousObjectCanInheritOpenLocalClass(useArtifact: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let artifactPath: String?
        if useArtifact {
            artifactPath = try Self.buildStdlibArtifact()
        } else {
            TestStdlibCache.shared.prepare()
            guard CompilerOptions.defaultStdlibLibraryPath != nil else {
                throw CompilerPipelineError.invalidInput("Expected the default stdlib cache to publish an artifact")
            }
            artifactPath = nil
        }
        let source = """
        class A {
            var a: String = "Fail"

            init {
                open class B() {
                    open fun s(): String = "O"
                }

                val o = object : B() {
                    override fun s(): String = "K"
                }
                a = B().s() + o.s()
            }
        }

        fun original(): String = A().a

        fun minimum(): String {
            open class B {
                open fun s(): String = "O"
            }
            val x = object : B() {
                override fun s(): String = "K"
            }
            return x.s()
        }

        fun namedLocalControl(): String {
            open class B {
                open fun s(): String = "O"
            }
            class C : B() {
                override fun s(): String = "K"
            }
            return C().s()
        }

        open class TopLevelBase {
            open fun s(): String = "O"
        }

        fun topLevelAnonymousControl(): String {
            val x = object : TopLevelBase() {
                override fun s(): String = "K"
            }
            return x.s()
        }

        fun main() {
            println(original())
            println(minimum())
            println(namedLocalControl())
            println(topLevelAnonymousControl())
        }
        """

        try withTemporaryFile(contents: source) { inputPath in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let ctx = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "LocalOpenClassAnonymousObject",
                outputPath: output,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: !useArtifact,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [], timeout: 10)
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "OK\nK\nK\nK\n")
            #expect(result.stderr.isEmpty)
        }
    }
}

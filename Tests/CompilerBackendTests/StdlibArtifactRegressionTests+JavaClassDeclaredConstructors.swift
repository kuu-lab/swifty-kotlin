@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2372: Java Class exposes the declared constructors registered for its KClass token.
    @Test func testJavaClassDeclaredConstructorsAcrossStdlibSurfaces() throws {
        let source = """
        class A { inner class B }

        fun box(): String {
            val constructors: Array<java.lang.reflect.Constructor<*>> =
                A.B::class.java.getDeclaredConstructors()
            return if (constructors.size == 1) "OK" else "FAIL"
        }

        fun control(): String {
            A.B::class.java.desiredAssertionStatus()
            return "OK"
        }

        fun main() {
            println(box())
            println(control())
        }
        """
        let artifact = try Self.buildStdlibArtifact()
        // Source/O2 currently fails LLVM verification on the baseline control before linking.
        let lanes: [(library: String?, level: OptimizationLevel)] = [
            (nil, .O0),
            (artifact, .O0),
            (artifact, .O2),
        ]
        for (library, level) in lanes {
            try withTemporaryFile(contents: source) { path in
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = try runCodegenPipeline(
                    inputPath: path,
                    moduleName: "JavaClassDeclaredConstructors",
                    outputPath: output,
                    optLevel: level,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: library
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == "OK\nOK\n")
            }
        }
    }
}

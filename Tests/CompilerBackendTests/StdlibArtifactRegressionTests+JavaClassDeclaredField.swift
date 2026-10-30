@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2186: enum entry fields expose runtime-retained annotations through java.lang.reflect.Field.
    @Test
    func javaClassDeclaredEnumFieldAnnotationsAcrossStdlibSurfaces() throws {
        let source = """
        @Retention(AnnotationRetention.RUNTIME)
        annotation class First

        @Retention(AnnotationRetention.RUNTIME)
        annotation class Second(val value: String)

        enum class E {
            @First
            E1 {
                fun foo() = "something"
            },

            @Second("OK")
            E2
        }

        fun minimalProbe(type: Class<E>) = type.getDeclaredField("E1")

        fun box(): String {
            val e = E::class.java
            if (!e.desiredAssertionStatus()) return "Fail positive control"
            val e1 = e.getDeclaredField(E.E1.toString()).getAnnotations()
            if (e1.size != 1) return "Fail E1 size: ${e1.toList()}"
            if (e1[0].annotationClass.java != First::class.java) return "Fail E1: ${e1.toList()}"

            val e2 = e.getDeclaredField(E.E2.toString()).getAnnotations()
            if (e2.size != 1) return "Fail E2 size: ${e2.toList()}"
            if (e2[0].annotationClass.java != Second::class.java) return "Fail E2: ${e2.toList()}"

            return (e2[0] as Second).value
        }

        fun main() { print(box()) }
        """
        let artifact = try Self.buildStdlibArtifact()
        let lanes: [(name: String, includeStdlib: Bool, artifact: String?, optimization: OptimizationLevel)] = [
            ("source O0", true, nil, .O0),
            ("source O2", true, nil, .O2),
            ("fresh .kklib O0", false, artifact, .O0),
            ("fresh .kklib O2", false, artifact, .O2),
        ]

        for lane in lanes {
            try withTemporaryFile(contents: source) { input in
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let options = CompilerOptions(
                    moduleName: "KUU2186JavaClassDeclaredField",
                    inputs: [input],
                    outputPath: output,
                    emit: .executable,
                    target: defaultTargetTriple(),
                    optLevel: lane.optimization,
                    includeStdlib: lane.includeStdlib,
                    stdlibLibraryPath: lane.artifact,
                    allowDefaultStdlibLibrary: false
                )
                try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(lane.name): \(result.stderr)")
                #expect(result.stderr.isEmpty, "\(lane.name): \(result.stderr)")
                #expect(result.stdout == "OK", "\(lane.name): \(result.stdout)")
            }
        }
    }

    @Test
    func javaClassDeclaredFieldMissingNameUsesNoSuchFieldPanicContract() throws {
        let source = """
        enum class E { VALUE }
        fun main() { E::class.java.getDeclaredField("MISSING") }
        """
        try withTemporaryFile(contents: source) { input in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let options = CompilerOptions(
                moduleName: "KUU2186MissingJavaField",
                inputs: [input],
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: .O0,
                includeStdlib: true,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

            var failure: CommandResult?
            do {
                _ = try CommandRunner.run(executable: output, arguments: [])
            } catch let CommandRunnerError.nonZeroExit(result) {
                failure = result
            }
            #expect(failure != nil, "Missing enum field lookup should stop with the documented native panic")
            #expect(failure?.stderr.contains("java.lang.NoSuchFieldException: MISSING") == true)
        }
    }
}

@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [0, 2])
    func javaClassCanonicalNameMatchesJvmFromSource(optimization: Int) throws {
        try runJavaClassCanonicalNameRegression(fromSource: true, optimization: optimization)
    }

    @Test(arguments: [0, 2])
    func javaClassCanonicalNameMatchesJvmFromFreshArtifact(optimization: Int) throws {
        try runJavaClassCanonicalNameRegression(fromSource: false, optimization: optimization)
    }

    private func runJavaClassCanonicalNameRegression(fromSource: Bool, optimization: Int) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repository.appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/KUU-2392/javaPrimitiveType.kt"
        )
        let publicFixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let publicFixtureInPackage = "package canonicalnames\n" + publicFixture
        // KUU-2391 owns the bundled Java Void classifier; this stub isolates canonicalName here.
        let javaLangVoidStub = "package java.lang\nclass Void\n"
        let minimalRepro = """
        package canonicalnames
        fun canonicalNameMinimalRepro(): String {
            val c = String::class.java
            return if (c.canonicalName == "java.lang.String") "OK" else "FAIL"
        }
        """
        let typeNameChecks = """
        package canonicalnames
        class CanonicalNameSample
        class CanonicalNameOuter { class Inner }
        fun canonicalNameTypeNamesMatch(): Boolean =
            String::class.java.canonicalName == "java.lang.String" &&
                Any::class.java.canonicalName == "java.lang.Object" &&
                CanonicalNameSample::class.java.canonicalName == "canonicalnames.CanonicalNameSample" &&
                CanonicalNameOuter.Inner::class.java.canonicalName == "canonicalnames.CanonicalNameOuter.Inner" &&
                kotlin.RuntimeException::class.java.canonicalName == "java.lang.RuntimeException"
        """
        let runner = """
        package canonicalnames
        fun main() {
            println(box())
            println(canonicalNameMinimalRepro())
            println(canonicalNameTypeNamesMatch())
        }
        """
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))

        try withTemporaryFiles(contents: [javaLangVoidStub, publicFixtureInPackage, minimalRepro, typeNameChecks, runner]) { inputs in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let options = CompilerOptions(
                moduleName: "KUU2392JavaClassCanonicalName",
                inputs: inputs,
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == "OK\nOK\ntrue\n")
        }
    }
}

import Foundation
import Testing
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport

@Suite(.serialized)
struct JavaLangSystemGetPropertyTests {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/KUU-2229")
    }

    @Test(arguments: [0, 2])
    func upstreamHelperAndSystemPropertyOverloadsUseFreshStdlibArtifact(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let consumerPath = directory.appendingPathComponent("consumer.kt").path
        let defaultImportsPath = directory.appendingPathComponent("default-imports.kt").path
        let outputPath = directory.appendingPathComponent("consumer").path
        let defaultImports = """
        package kuu2229

        fun defaultImportedProperty(name: String): String? = System.getProperty(name)
        fun defaultImportedPropertyWithDefault(name: String, fallback: String): String = System.getProperty(name, fallback)
        """
        try defaultImports.write(toFile: defaultImportsPath, atomically: true, encoding: .utf8)

        let source = """
        package kuu2229

        import java.lang.System
        import io.kjson.util.getIntProperty

        fun property(name: String): String? = java.lang.System.getProperty(name)
        fun importedProperty(name: String): String? = System.getProperty(name)
        fun propertyWithDefault(name: String, defaultValue: String): String = System.getProperty(name, defaultValue)

        fun main() {
            println(property("KSWIFTK_KUU2229_PRESENT"))
            println(importedProperty("KSWIFTK_KUU2229_PRESENT"))
            println(defaultImportedProperty("KSWIFTK_KUU2229_PRESENT"))
            println(property("KSWIFTK_KUU2229_MISSING") == null)
            println(propertyWithDefault("KSWIFTK_KUU2229_MISSING", "fallback"))
            println(defaultImportedPropertyWithDefault("KSWIFTK_KUU2229_MISSING", "default-import-fallback"))
            println(propertyWithDefault("KSWIFTK_KUU2229_EMPTY", "fallback").length)
            println(getIntProperty("KSWIFTK_KUU2229_INTEGER", 11))
            println(getIntProperty("KSWIFTK_KUU2229_MISSING", 12))
            System.gc()
            java.lang.System.gc()
            println("gc")
        }
        """
        try source.write(toFile: consumerPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KUU2229SystemGetProperty",
            inputs: [
                fixtures.appendingPathComponent("JSONException.kt").path,
                fixtures.appendingPathComponent("SystemProperty.kt").path,
                defaultImportsPath,
                consumerPath,
            ],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: [
                "-u", "KSWIFTK_KUU2229_PRESENT",
                "-u", "KSWIFTK_KUU2229_EMPTY",
                "-u", "KSWIFTK_KUU2229_INTEGER",
                "-u", "KSWIFTK_KUU2229_MISSING",
                "KSWIFTK_KUU2229_PRESENT=configured",
                "KSWIFTK_KUU2229_EMPTY=",
                "KSWIFTK_KUU2229_INTEGER=37",
                outputPath,
            ]
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout == "configured\nconfigured\nconfigured\ntrue\nfallback\ndefault-import-fallback\n0\n37\n12\ngc\n")
        #expect(result.stderr.isEmpty, "stderr: \(result.stderr)")
    }
}

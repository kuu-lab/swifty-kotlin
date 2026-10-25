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

    @Test(arguments: [0, 2])
    func environmentPropertiesAndClockFunctionsAreAvailable(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let consumerPath = directory.appendingPathComponent("consumer.kt").path
        let outputPath = directory.appendingPathComponent("consumer").path
        let source = """
        fun main() {
            println(java.lang.System.getenv("KSWIFTK_KUU3342_ENV"))
            println(java.lang.System.getenv()["KSWIFTK_KUU3342_ENV"])
            println(java.lang.System.setProperty("kuu3342.key", "first") == null)
            println(java.lang.System.getProperty("kuu3342.key"))
            println(java.lang.System.setProperty("kuu3342.key", "second"))
            println(java.lang.System.clearProperty("kuu3342.key"))
            println(java.lang.System.getProperty("kuu3342.key") == null)
            println(java.lang.System.currentTimeMillis() != 0L)
            println(java.lang.System.nanoTime() != 0L)
        }
        """
        try source.write(toFile: consumerPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KUU3342SystemApis",
            inputs: [consumerPath],
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
                "-u", "KSWIFTK_KUU3342_ENV",
                "KSWIFTK_KUU3342_ENV=configured",
                outputPath,
            ]
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(
            result.stdout == "configured\nconfigured\ntrue\nfirst\nfirst\nsecond\ntrue\ntrue\ntrue\n"
        )
        #expect(result.stderr.isEmpty, "stderr: \(result.stderr)")
    }

    @Test(arguments: [0, 2])
    func standardSystemPropertiesAndLineSeparatorAreAvailable(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let consumerPath = directory.appendingPathComponent("consumer.kt").path
        let outputPath = directory.appendingPathComponent("consumer").path
        let source = """
        fun main() {
            println(java.lang.System.getProperty("java.vm.name")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("java.version")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("java.class.path") != null)
            println(java.lang.System.getProperty("sun.java.command")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("sun.arch.data.model") == "\(Int.bitWidth)")
            println(java.lang.System.getProperty("sun.cpu.endian") == "little" || java.lang.System.getProperty("sun.cpu.endian") == "big")
            println(java.lang.System.getProperty("os.name")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("os.version")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("os.arch")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("user.name")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("user.home")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("user.dir")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("java.io.tmpdir")?.isNotEmpty() == true)
            println(java.lang.System.getProperty("file.separator") == "/")
            println(java.lang.System.getProperty("path.separator") == ":")
            println(java.lang.System.getProperty("line.separator")?.length == 1)
            println(java.lang.System.lineSeparator() == java.lang.System.getProperty("line.separator"))
            println(kotlin.system.System.lineSeparator() == java.lang.System.lineSeparator())
            println(java.lang.System.getProperty("KSWIFTK_KUU2798_CUSTOM") == "configured")
            println(java.lang.System.getProperty("KSWIFTK_KUU2798_UNKNOWN") == null)
        }
        """
        try source.write(toFile: consumerPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KUU2798SystemProperties",
            inputs: [consumerPath],
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
            arguments: ["KSWIFTK_KUU2798_CUSTOM=configured", outputPath]
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout == Array(repeating: "true", count: 20).joined(separator: "\n") + "\n")
        #expect(result.stderr.isEmpty, "stderr: \(result.stderr)")
    }
}

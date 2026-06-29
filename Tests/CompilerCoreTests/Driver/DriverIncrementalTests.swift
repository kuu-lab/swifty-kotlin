#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DriverIncrementalTests {
    private var tempDir: String
    private var outputPath: String

    init() {
        tempDir = NSTemporaryDirectory() + "DriverIncrementalTest_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        outputPath = tempDir + "/output"
    }

    private func makeDriver() -> CompilerDriver {
        CompilerDriver()
    }

    private func kirOutputPath() -> String {
        outputPath + ".kir"
    }

    private func cachedOutputArtifactPath(in cachePath: String) throws -> String {
        let artifactsPath = cachePath + "/artifacts"
        let enumerator = try #require(FileManager.default.enumerator(atPath: artifactsPath))
        for case let path as String in enumerator where URL(fileURLWithPath: path).lastPathComponent == "output" {
            let output = artifactsPath + "/" + path
            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: output, isDirectory: &isDirectory), !isDirectory.boolValue {
                return output
            }
        }
        Issue.record("Expected cached output artifact under \(artifactsPath)"); return artifactsPath + "/missing"
    }

    // MARK: - time-phases flag

    @Test
    func testTimePhasesFlagEnablesPhaseTimer() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["time-phases"]
            )
            let result = driver.runForTesting(options: options)
            #expect(result.exitCode == 0,
                           "KIR dump with time-phases should succeed. Diagnostics: \(result.diagnostics.map(\.message))")
        }
    }

    // MARK: - incremental flag

    @Test
    func testIncrementalFlagEnablesIncrementalCompilation() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )
            let result = driver.runForTesting(options: options)
            #expect(result.exitCode == 0,
                           "KIR dump with incremental should succeed. Diagnostics: \(result.diagnostics.map(\.message))")
            // Cache files should have been written
            #expect(FileManager.default.fileExists(atPath: cachePath + "/manifest.json"))
            #expect(FileManager.default.fileExists(atPath: cachePath + "/deps.json"))
            #expect(FileManager.default.fileExists(atPath: cachePath + "/frontend.json"))
        }
    }

    @Test
    func testIncrementalSecondBuildUsesCache() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )
            // First build
            let result1 = driver.runForTesting(options: options)
            #expect(result1.exitCode == 0)

            // Second build (no changes)
            let result2 = driver.runForTesting(options: options)
            #expect(result2.exitCode == 0)
        }
    }

    @Test
    func testIncrementalNoOpBuildRestoresCachedOutputArtifact() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )

            let first = driver.runForTesting(options: options)
            #expect(first.exitCode == 0,
                           "Initial incremental build should succeed. Diagnostics: \(first.diagnostics.map(\.message))")

            let sentinel = "// cached artifact\n"
            try sentinel.write(toFile: cachedOutputArtifactPath(in: cachePath), atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: kirOutputPath())

            let second = driver.runForTesting(options: options)
            #expect(second.exitCode == 0,
                           "No-op incremental build should restore cached artifact. Diagnostics: \(second.diagnostics.map(\.message))")
            #expect(try String(contentsOfFile: kirOutputPath(), encoding: .utf8) == sentinel)
        }
    }

    @Test
    func testIncrementalChangedInputDoesNotRestoreStaleOutputArtifact() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )

            let first = driver.runForTesting(options: options)
            #expect(first.exitCode == 0,
                           "Initial incremental build should succeed. Diagnostics: \(first.diagnostics.map(\.message))")

            let sentinel = "// stale cached artifact\n"
            try sentinel.write(toFile: cachedOutputArtifactPath(in: cachePath), atomically: true, encoding: .utf8)
            try "fun main() { println(\"changed\") }".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: kirOutputPath())

            let second = driver.runForTesting(options: options)
            #expect(second.exitCode == 0,
                           "Changed input should fall back to a full build. Diagnostics: \(second.diagnostics.map(\.message))")
            #expect(try String(contentsOfFile: kirOutputPath(), encoding: .utf8) != sentinel)
        }
    }

    @Test
    func testIncrementalChangedInputReusesUnchangedFrontendStateForFullOutput() throws {
        try withTemporaryFiles(contents: [
            "fun kept(): String = \"kept\"",
            "fun changed(): String = kept()",
        ]) { paths in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: paths,
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )

            let first = driver.runForTesting(options: options)
            #expect(first.exitCode == 0,
                           "Initial incremental build should succeed. Diagnostics: \(first.diagnostics.map(\.message))")

            try "fun changedAgain(): String = kept()".write(toFile: paths[1], atomically: true, encoding: .utf8)

            let second = driver.runForTesting(options: options)
            #expect(second.exitCode == 0,
                           "Changed input should compile using cached unchanged frontend state. Diagnostics: \(second.diagnostics.map(\.message))")

            let kir = try String(contentsOfFile: kirOutputPath(), encoding: .utf8)
            #expect(kir.contains(" kept params="), "Output should retain declarations from the unchanged file")
            #expect(kir.contains(" changedAgain params="), "Output should include declarations rebuilt from the changed file")
            #expect(!(kir.contains(" changed params=")), "Output should not retain stale declarations from the old changed file")
        }
    }

    @Test
    func testIncrementalChangedConfigurationDoesNotRestoreStaleOutputArtifact() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )

            let first = driver.runForTesting(options: options)
            #expect(first.exitCode == 0,
                           "Initial incremental build should succeed. Diagnostics: \(first.diagnostics.map(\.message))")

            let sentinel = "// stale cached artifact\n"
            try sentinel.write(toFile: cachedOutputArtifactPath(in: cachePath), atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: kirOutputPath())

            let changedOptions = CompilerOptions(
                moduleName: "ChangedTest",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )
            let second = driver.runForTesting(options: changedOptions)
            #expect(second.exitCode == 0,
                           "Changed build configuration should fall back to a full build. Diagnostics: \(second.diagnostics.map(\.message))")
            #expect(try String(contentsOfFile: kirOutputPath(), encoding: .utf8) != sentinel)
        }
    }

    // MARK: - ICE fallback

    @Test
    func testICEFallbackDiagnosticForUnknownError() {
        struct CustomError: Error {}
        let result = CompilerDriver.fallbackDiagnostic(for: CustomError())
        #expect(result == nil)
    }

    // MARK: - Multiple files with dependencies

    @Test
    func testIncrementalWithMultipleFiles() throws {
        try withTemporaryFiles(contents: [
            "fun greet(): String = \"Hello\"",
            "fun main() { println(greet()) }",
        ]) { paths in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: paths,
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )
            let result = driver.runForTesting(options: options)
            #expect(result.exitCode == 0,
                           "Multi-file incremental should succeed. Diagnostics: \(result.diagnostics.map(\.message))")
        }
    }

    // MARK: - run method

    @Test
    func testRunMethodReturnsExitCode() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple()
            )
            let exitCode = driver.run(options: options)
            #expect(exitCode == 0)
        }
    }

    @Test
    func testRunMethodWithErrorReturns1() {
        let driver = makeDriver()
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: outputPath,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let exitCode = driver.run(options: options)
        #expect(exitCode == 1)
    }
}
#endif

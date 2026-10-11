@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExecutableArgumentsBackendTests {
    private func fixture(_ name: String) throws -> String {
        let pins = [
            "DesignatedEntryControls.kt": "065863ff1dcae0a48f1d62c8110c947e40d1ee079276907bbaf9df55904efaca",
            "MainArgsExitControls.kt": "7022610d283b4500a015dad3c7f1347eb00766cbddd3df48175e0804ef3f4d21",
            "MainArgsInitializationControls.kt": "d1b661fe97655a4b1737bc7b0dd755b35ef1815c49b1ebec7cedb8ceec45f05a",
            "MainArgsOracle.kt": "163c68696a776ae561b57e8ce4075a1bc1a7f3bebf7c663b3d7599e29fcfa8c8",
            "args.json": "49f2cf6c50142ffc36f56a6878c1ac29202de25c7a55c46e85a07d89066ac791",
            "designated.expected.stdout": "5e91fbcee9997830fd574e2c56a53763b6fc5ce1224749bb457f928c1618195f",
            "expected.empty.stdout": "d950b4e86f37941c3520e2f6072e72fac7dd04015e53cf27644030cfef1c1216",
            "expected.multiple.stdout": "44929e74c00d10f03cbad558526eceec659f2a1a4971992c1996af2c64a042aa",
            "initialization.expected.stdout": "cf4f8c0a5f20f54e36365d9a2a0290b4cde1e53b44981f6df3755cad38cc35eb",
        ]
        let source = try repositoryFileSource("Tests/CompilerBackendTests/Fixtures/ExecutableArguments/\(name)")
        let expectedHash = try #require(pins[name])
        try #require(FileFingerprint.sha256Hex(Data(source.utf8)) == expectedHash)
        return source
    }

    private func options(
        path: String, output: String, library: Bool, level: OptimizationLevel,
        entry: String? = nil
    ) throws -> CompilerOptions {
        let result = CompilerOptions(
            moduleName: "EntryArguments", inputs: [path], outputPath: output,
            emit: .executable, target: defaultTargetTriple(), optLevel: level,
            allowDefaultStdlibLibrary: library, entryPointFQName: entry
        )
        if library {
            guard let artifact = result.stdlibLibraryPath,
                  FileManager.default.fileExists(atPath: artifact + "/manifest.json") else {
                throw TestCompilationFailure(description: "Library mode needs a fresh stdlib artifact")
            }
            let manifest = try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: artifact + "/manifest.json"))
            ) as? [String: Any]
            guard manifest?["moduleName"] as? String == "KSwiftKStdlib",
                  manifest?["kotlinLanguageVersion"] as? String == "2.3.10",
                  manifest?["formatVersion"] as? Int == 1 else {
                throw TestCompilationFailure(description: "Library mode requires the Kotlin 2.3.10 stdlib manifest")
            }
        } else if result.stdlibLibraryPath != nil || !result.includeStdlib {
            throw TestCompilationFailure(description: "Source mode must actually inject source stdlib")
        }
        return result
    }

    private func writeJSON(_ value: [String: Any], to path: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: path)
    }

    private func compile(
        _ options: CompilerOptions, directory: URL
    ) throws -> (exitCode: Int, diagnostics: [Diagnostic]) {
        try writeJSON([
            "invocation": "CompilerDriver.runForTesting",
            "inputs": options.inputs,
            "outputPath": options.outputPath,
            "moduleName": options.moduleName,
            "target": String(describing: options.target),
            "optimization": options.optLevel.rawValue,
            "emit": "executable",
            "includeStdlib": options.includeStdlib,
            "allowDefaultStdlibLibrary": options.allowDefaultStdlibLibrary,
            "stdlibLibraryPath": options.stdlibLibraryPath.map { $0 as Any } ?? NSNull(),
            "entryPointFQName": options.entryPointFQName.map { $0 as Any } ?? NSNull(),
        ], to: directory.appendingPathComponent("compilation.request.json"))
        let result = makeTestDriver().runForTesting(options: options)
        try Data(String(describing: result).utf8).write(to: directory.appendingPathComponent("compilation.result.txt"))
        try writeJSON([
            "exitCode": result.exitCode,
            "diagnosticCount": result.diagnostics.count,
            "errorCodes": result.diagnostics.filter { $0.severity == .error }.map(\.code),
        ], to: directory.appendingPathComponent("compilation.exit.json"))
        return result
    }

    private func run(
        _ executable: String, _ args: [String], label: String, expectedStdout: String
    ) throws -> CommandResult {
        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent()
        let expected = Data(expectedStdout.utf8)
        try expected.write(to: directory.appendingPathComponent(label + ".expected.stdout"))
        try writeJSON([
            "argv": [executable] + args, "timeoutSeconds": 10,
            "expectedStdoutSHA256": FileFingerprint.sha256Hex(expected),
        ], to: directory.appendingPathComponent(label + ".command.json"))
        let result: CommandResult
        do { result = try CommandRunner.run(executable: executable, arguments: args, timeout: 10) }
        catch let CommandRunnerError.nonZeroExit(failed) { result = failed }
        catch {
            // CommandRunner does not expose partial streams on launch/timeout errors.
            try Data(String(describing: error).utf8).write(to: directory.appendingPathComponent(label + ".error.txt"))
            throw error
        }
        let stdout = Data(result.stdout.utf8)
        let stderr = Data(result.stderr.utf8)
        try stdout.write(to: directory.appendingPathComponent(label + ".stdout"))
        try stderr.write(to: directory.appendingPathComponent(label + ".stderr"))
        try writeJSON([
            "exitCode": result.exitCode,
            "stdoutSHA256": FileFingerprint.sha256Hex(stdout),
            "stderrSHA256": FileFingerprint.sha256Hex(stderr),
        ], to: directory.appendingPathComponent(label + ".exit.json"))
        try #require(stdout == expected)
        return result
    }

    private func withExecutable(
        source: String, library: Bool, level: OptimizationLevel, entry: String? = nil,
        body: (String) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer {
            if completed { try? FileManager.default.removeItem(at: directory) }
            else { print("KUU1770_RETAINED_ARTIFACTS \(directory.path)") }
        }
        let input = directory.appendingPathComponent("Main.kt")
        let original = Data(source.utf8)
        try original.write(to: input)
        let output = directory.appendingPathComponent("entry").path
        let selected = try options(path: input.path, output: output, library: library, level: level, entry: entry)
        var libraryPins: [String: String] = [:]
        if let artifact = selected.stdlibLibraryPath {
            for name in ["manifest.json", "metadata.bin"] {
                let path = URL(fileURLWithPath: artifact).appendingPathComponent(name)
                let data = try Data(contentsOf: path)
                libraryPins[path.path] = FileFingerprint.sha256Hex(data)
                if name == "manifest.json" { try data.write(to: directory.appendingPathComponent("stdlib.manifest.json")) }
            }
        }
        try writeJSON([
            "sourcePath": input.path, "sourceSHA256": FileFingerprint.sha256Hex(original),
            "libraryFilesSHA256": libraryPins,
        ], to: directory.appendingPathComponent("input.pins.json"))
        let result = try compile(selected, directory: directory)
        try assertCompilationSucceeded(result)
        try #require(FileManager.default.isExecutableFile(atPath: output))
        let executableHash = FileFingerprint.sha256Hex(try Data(contentsOf: URL(fileURLWithPath: output)))
        try body(output)
        try #require(try Data(contentsOf: input) == original)
        try #require(FileFingerprint.sha256Hex(try Data(contentsOf: URL(fileURLWithPath: output))) == executableHash)
        for (path, hash) in libraryPins {
            try #require(FileFingerprint.sha256Hex(try Data(contentsOf: URL(fileURLWithPath: path))) == hash)
        }
        completed = true
    }

    // The fixture and expected bytes come from the pinned Kotlin 2.3.10 JVM
    // argv oracle. Each cell compiles once and runs empty and six-argument cases.
    @Test(arguments: [false, true], [0, 2])
    func argumentsMatchFixedJVMOracleAcrossSourceLibraryO0O2(library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let args = try JSONDecoder().decode([String].self, from: Data(fixture("args.json").utf8))
        try #require(args.count == 6)
        try withExecutable(source: fixture("MainArgsOracle.kt"), library: library, level: level) { output in
            let empty = try run(output, [], label: "empty", expectedStdout: fixture("expected.empty.stdout"))
            try #require(empty.exitCode == 0 && empty.stderr.isEmpty)
            let multiple = try run(output, args, label: "multiple", expectedStdout: fixture("expected.multiple.stdout"))
            try #require(multiple.exitCode == 0 && multiple.stderr.isEmpty)
        }
    }

    // These two cells exercise the selected args entry's startup guard. The
    // existing noargs ModuleStartup regression covers other-main calls.
    @Test(arguments: [false, true])
    func argumentsEntryReentryDoesNotRepeatInitializers(library: Bool) throws {
        try withExecutable(source: fixture("MainArgsInitializationControls.kt"), library: library, level: .O2) { output in
            let reentered = try run(output, ["first"], label: "reentry", expectedStdout: fixture("initialization.expected.stdout"))
            try #require(reentered.exitCode == 0 && reentered.stderr.isEmpty)
        }
    }

    @Test
    func argumentsEntryPreservesThrownChannelAndExitProcess() throws {
        try withExecutable(source: fixture("MainArgsExitControls.kt"), library: true, level: .O2) { output in
            let thrown = try run(output, ["throw", "payload"], label: "throw", expectedStdout: "before:payload\n")
            try #require(thrown.exitCode == 1)
            try #require(thrown.stderr.contains("KSWIFTK-LINK-0003"))
            let exited = try run(output, ["exit"], label: "exit", expectedStdout: "before-exit\n")
            try #require(exited.exitCode == 23 && exited.stderr.isEmpty)
        }
    }

    @Test
    func noArgumentEntryIgnoresHostArgumentsAndItsReturnValue() throws {
        try withExecutable(source: "fun main(): Any { println(\"noargs\"); return 42 }", library: true, level: .O2) { output in
            let executed = try run(output, ["ignored", "日本語"], label: "noargs", expectedStdout: "noargs\n")
            try #require(executed.exitCode == 0 && executed.stderr.isEmpty)
        }
    }

    @Test
    func covariantStringArrayEntryReceivesArguments() throws {
        try withExecutable(source: "fun main(args: Array<out String>) { println(args[0]) }", library: true, level: .O2) { output in
            let executed = try run(output, ["covariant"], label: "covariant", expectedStdout: "covariant\n")
            try #require(executed.exitCode == 0 && executed.stderr.isEmpty)
        }
    }

    @Test(arguments: [
        "fun main(x: Int) {}",
        "fun main(args: Array<Int>) {}",
        "fun main(args: Array<String>?) {}",
        "fun main(args: Array<String?>) {}",
        "fun main(args: Array<in String>) {}",
        "fun main(args: Array<*>) {}",
        "fun main(a: Int, b: Int) {}",
        "fun main(x: Int) {}\nfun main(args: Array<String>) {}",
    ])
    func unsupportedEntryShapeHasLinkerDiagnostic(source: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer {
            if completed { try? FileManager.default.removeItem(at: directory) }
            else { print("KUU1770_RETAINED_ARTIFACTS \(directory.path)") }
        }
        let input = directory.appendingPathComponent("Main.kt")
        let original = Data(source.utf8)
        try original.write(to: input)
        let output = directory.appendingPathComponent("entry").path
        let selected = try options(path: input.path, output: output, library: true, level: .O0)
        let result = try compile(selected, directory: directory)
        try #require(result.exitCode != 0)
        try #require(result.diagnostics.contains { $0.code == "KSWIFTK-LINK-0002" })
        try #require(!FileManager.default.fileExists(atPath: output))
        try #require(try Data(contentsOf: input) == original)
        completed = true
    }

    @Test
    func designatedArgumentsEntryDoesNotRunOriginalMain() throws {
        try withExecutable(source: fixture("DesignatedEntryControls.kt"), library: true, level: .O2,
                           entry: "entrycontrols.launch") { output in
            let executed = try run(output, ["hello"], label: "designated", expectedStdout: fixture("designated.expected.stdout"))
            try #require(executed.exitCode == 0 && executed.stderr.isEmpty)
        }
    }
}

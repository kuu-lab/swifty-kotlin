// Scratch implementation proposal: all candidate lanes below remain NOT_RUN.
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testRunBlockingContextContractsAndTypedCaptures(useLibrary: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let fixtures = runBlocking1765Fixtures()
        let contract = try Data(contentsOf: fixtures.appendingPathComponent("PortableContract.kt"))
        let controls = try Data(contentsOf: fixtures.appendingPathComponent("CompilerControls.kt"))
        let driver = try Data(contentsOf: fixtures.appendingPathComponent("driver.kt"))
        let expected = try Data(contentsOf: fixtures.appendingPathComponent("combined.expected.stdout"))
        try #require(FileFingerprint.sha256Hex(contract) == "f34032b694e88e017ff5049485efc2c92e9475600f02cdb2ebbb9000df5f9cb2")
        try #require(FileFingerprint.sha256Hex(controls) == "d86a36a3dbc7af8d1bd6d5c2c2355a67dc6d8a80a6faf8b8e584cd796f7b4a63")
        try #require(FileFingerprint.sha256Hex(driver) == "0c05e2b2560a73954c5049b4a805148dcdb07343617593b9bdf5314c054d1603")
        try #require(FileFingerprint.sha256Hex(expected) == "5b864281b4b3f5df8fb152cbd71bc27003d14375b352ecab0a2e04f2ef3e19f2")
        let inputs: [(String, Data)] = [
            // Prefix only: assertion bodies and stored captures stay unchanged.
            ("contract.kt", Data("package runblocking1765.contract\n".utf8) + contract),
            ("controls.kt", Data("package runblocking1765.controls\n".utf8) + controls),
            ("driver.kt", driver)
        ]
        try runBlocking1765Executable(inputs, expected: expected, level: level,
                                     useLibrary: useLibrary, entry: "main")
    }

    @Test(arguments: [0, 2])
    func testRunBlockingContextRealUserProducerAndSeparateConsumer(optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let fixtures = runBlocking1765Fixtures()
        let producer = try Data(contentsOf: fixtures.appendingPathComponent("producer.kt"))
        let consumer = try Data(contentsOf: fixtures.appendingPathComponent("consumer.kt"))
        let expected = try Data(contentsOf: fixtures.appendingPathComponent("producer.expected.stdout"))
        try #require(FileFingerprint.sha256Hex(producer) == "7d26953245d7c53f6795347860a83e1e1a753d3ee8290c3571e6cf9f6c77668a")
        try #require(FileFingerprint.sha256Hex(consumer) == "e337840d1e4fb222c542ed0eefd2ae0654ccc8b52c6093d8c2b05c965190643e")
        try #require(FileFingerprint.sha256Hex(expected) == "028d2e1de5582c6f52175fff8e473ddbe478b43e75d9d42e26b66ea6e307f79d")
        try runBlocking1765Executable([("consumer.kt", consumer)], expected: expected, level: level,
                                     useLibrary: true, entry: "runblocking1765.consumer.main",
                                     producer: producer)
    }
}

private func runBlocking1765Fixtures() -> URL {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { root.deleteLastPathComponent() }
    return root.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/RunBlockingContext", isDirectory: true)
}

private struct RunBlocking1765Artifact {
    let directory: URL
    let hashes: [String: String]
    func requireUnchanged() throws { try #require(runBlocking1765FileHashes(directory) == hashes) }
    func expectUnchanged() { #expect((try? runBlocking1765FileHashes(directory)) == hashes) }
}

private func runBlocking1765FileHashes(_ directory: URL) throws -> [String: String] {
    let enumerator = try #require(FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
    ))
    var hashes: [String: String] = [:]
    for case let path as URL in enumerator {
        let values = try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        try #require(values.isSymbolicLink != true, "Owned output and library snapshots cannot follow symlinks")
        if values.isRegularFile == true {
            let relative = String(path.path.dropFirst(directory.path.count + 1))
            hashes[relative] = FileFingerprint.sha256Hex(try Data(contentsOf: path))
        }
    }
    try #require(!hashes.isEmpty)
    return hashes
}

private func runBlocking1765Artifact(_ path: URL, expectedModule: String) throws -> RunBlocking1765Artifact {
    let manifest = try #require(JSONSerialization.jsonObject(with:
        Data(contentsOf: path.appendingPathComponent("manifest.json"))) as? [String: Any])
    try #require(manifest["moduleName"] as? String == expectedModule)
    try #require(manifest["formatVersion"] as? Int == 1)
    try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
    let objects = try #require(manifest["objects"] as? [String])
    try #require(!objects.isEmpty, "An actual object-producing library is required")
    for object in objects {
        let components = object.split(separator: "/", omittingEmptySubsequences: false)
        try #require(!object.hasPrefix("/") && !components.contains("..") && !components.contains(""))
        try #require(!Data(contentsOf: path.appendingPathComponent(object)).isEmpty)
    }
    try #require(!Data(contentsOf: path.appendingPathComponent("metadata.bin")).isEmpty)
    return RunBlocking1765Artifact(directory: path, hashes: try runBlocking1765FileHashes(path))
}

private func runBlocking1765Executable(
    _ sources: [(String, Data)], expected: Data, level: OptimizationLevel,
    useLibrary: Bool, entry: String, producer: Data? = nil
) throws {
    try #require(level == .O0 || level == .O2)
    var stdlib: RunBlocking1765Artifact?
    if useLibrary {
        TestStdlibCache.shared.prepare()
        let path = try #require(CompilerOptions.defaultStdlibLibraryPath,
                               "Artifact lane must bind a freshly published canonical stdlib")
        stdlib = try runBlocking1765Artifact(URL(fileURLWithPath: path), expectedModule: "KSwiftKStdlib")
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            stdlib!.directory.appendingPathComponent("manifest.json"))) as? [String: Any])
        try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        // Source-manifest integrity plus presence of the real private bridge
        // prevent an old one-argument synthetic stdlib artifact from passing.
        let metadata = try Data(contentsOf: stdlib!.directory.appendingPathComponent("metadata.bin"))
        let records = MetadataDecoder().decode(String(decoding: metadata, as: UTF8.self))
        try #require(records.contains { $0.fqName == "kotlinx.coroutines.runBlocking" && $0.kind == .function })
        try #require(records.contains { $0.fqName == "kotlinx.coroutines.__kkRunBlockingContext" && $0.kind == .function })
    }
    defer { stdlib?.expectUnchanged() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    print("KUU1765_RUNTIME_DIRECTORY \(directory.path)")
    var inputs: [String] = []
    for (name, contents) in sources {
        let input = directory.appendingPathComponent(name)
        try contents.write(to: input)
        inputs.append(input.path)
    }
    var userLibrary: RunBlocking1765Artifact?
    if let producer {
        let source = directory.appendingPathComponent("producer.kt")
        try producer.write(to: source)
        let output = directory.appendingPathComponent("producer")
        let options = CompilerOptions(
            moduleName: "KUU1765UserProducer", inputs: [source.path], outputPath: output.path,
            emit: .library, target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false
        )
        try #require(useLibrary && !options.includeStdlib && options.stdlibLibraryPath == stdlib?.directory.path)
        let compilation = makeTestDriver().runForTesting(options: options)
        try runBlocking1765SaveCompilation(compilation, options: options, into: directory, name: "producer")
        try assertCompilationSucceeded(compilation)
        userLibrary = try runBlocking1765Artifact(output.appendingPathExtension("kklib"), expectedModule: "KUU1765UserProducer")
        try #require(Data(contentsOf: source) == producer)
        try #require(!inputs.contains(source.path), "The consumer must import rather than recompile producer sources")
    }
    let executable = directory.appendingPathComponent("consumer")
    let options = CompilerOptions(
        moduleName: "KUU1765Consumer", inputs: inputs, outputPath: executable.path,
        emit: .executable, searchPaths: userLibrary.map { [$0.directory.path] } ?? [],
        target: TargetTriple.hostDefault(), optLevel: level,
        stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false,
        entryPointFQName: entry
    )
    try #require(options.optLevel == level && options.inputs == inputs)
    try #require(options.includeStdlib == !useLibrary && !options.allowDefaultStdlibLibrary)
    try #require(options.stdlibLibraryPath == stdlib?.directory.path && options.entryPointFQName == entry)
    let compilation = makeTestDriver().runForTesting(options: options)
    try runBlocking1765SaveCompilation(compilation, options: options, into: directory, name: "consumer")
    try assertCompilationSucceeded(compilation)
    try #require(FileManager.default.isExecutableFile(atPath: executable.path))
    let executableHash = FileFingerprint.sha256Hex(try Data(contentsOf: executable))
    let execution: CommandResult
    do {
        execution = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
    } catch CommandRunnerError.nonZeroExit(let failed) {
        try Data(failed.stdout.utf8).write(to: directory.appendingPathComponent("run.stdout"))
        try Data(failed.stderr.utf8).write(to: directory.appendingPathComponent("run.stderr"))
        try JSONSerialization.data(withJSONObject: ["status": "FAIL_EXECUTED", "exit_code": failed.exitCode],
                                   options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("run.failure.json"), options: .atomic)
        throw CommandRunnerError.nonZeroExit(failed)
    } catch {
        try JSONSerialization.data(withJSONObject: ["status": "FAIL_NO_SUCCESSFUL_COMPLETION",
            "error": String(describing: error), "timeout_seconds": 10], options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("run.failure.json"), options: .atomic)
        throw error
    }
    try Data(execution.stdout.utf8).write(to: directory.appendingPathComponent("run.stdout"))
    try Data(execution.stderr.utf8).write(to: directory.appendingPathComponent("run.stderr"))
    try #require(execution.exitCode == 0, "\(execution.stderr)")
    try #require(execution.stderr.isEmpty)
    try #require(Data(execution.stdout.utf8) == expected, "All checks and original rows must execute")
    for (name, contents) in sources { try #require(Data(contentsOf: directory.appendingPathComponent(name)) == contents) }
    try stdlib?.requireUnchanged()
    try userLibrary?.requireUnchanged()
    try #require(FileFingerprint.sha256Hex(Data(contentsOf: executable)) == executableHash)
    // No cleanup on failure. Keep sources and both raw streams on success too;
    // only the completed executable and its known direct object are removed.
    try Data(execution.stdout.utf8).write(to: directory.appendingPathComponent("run.stdout"))
    try Data(execution.stderr.utf8).write(to: directory.appendingPathComponent("run.stderr"))
    let proof: [String: Any] = [
        "status": "PASS_PROOF_BEFORE_OUTPUT_CLEANUP", "exit_code": execution.exitCode,
        "stdout_exact": true, "timeout_seconds": 10, "directory": directory.path,
        "stdlib_files": stdlib?.hashes ?? [:], "producer_files": userLibrary?.hashes ?? [:],
        "owned_files": try runBlocking1765FileHashes(directory), "executable_sha256": executableHash
    ]
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("receipt.json"), options: .atomic)
    var removed: [String: String] = [:]
    for output in [executable, executable.appendingPathExtension("o")] {
        if FileManager.default.fileExists(atPath: output.path) {
            try #require(output.deletingLastPathComponent() == directory)
            try #require(output.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
            removed[output.lastPathComponent] = FileFingerprint.sha256Hex(try Data(contentsOf: output))
            try FileManager.default.removeItem(at: output)
            try #require(!FileManager.default.fileExists(atPath: output.path))
        }
    }
    try JSONSerialization.data(withJSONObject: ["status": "ONLY_SUCCESSFUL_OWNED_OUTPUTS_REMOVED",
        "removed_sha256": removed, "sources_and_raw_streams_retained": true], options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("cleanup.receipt.json"), options: .atomic)
}

private func runBlocking1765SaveCompilation(
    _ result: (exitCode: Int, diagnostics: [Diagnostic]), options: CompilerOptions, into directory: URL, name: String
) throws {
    let diagnostics = result.diagnostics.map { ["code": $0.code, "message": $0.message,
                                               "severity": String(describing: $0.severity)] }
    let proof: [String: Any] = ["status": "ACTUAL_COMPILER_COMPLETION", "exit_code": result.exitCode,
        "diagnostics": diagnostics, "inputs": options.inputs, "output": options.outputPath,
        "optimization": options.optLevel.rawValue, "stdlib": options.stdlibLibraryPath ?? "",
        "search_paths": options.searchPaths, "include_stdlib": options.includeStdlib,
        "allow_default_stdlib_library": options.allowDefaultStdlibLibrary]
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent(name + ".compile.receipt.json"), options: .atomic)
}

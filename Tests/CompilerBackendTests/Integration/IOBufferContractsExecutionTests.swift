@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct IOBufferContractsExecutionTests {

    private func fixtures() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/IOBuffer1729")
    }

    private func library(_ requested: Bool) throws -> IOBufferArtifactSnapshot? {
        guard requested else { return nil }
        TestStdlibCache.shared.prepare()
        let path = try #require(CompilerOptions.defaultStdlibLibraryPath, "Actual current stdlib artifact required")
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let manifest = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        ) as? [String: Any])
        try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
        try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
        try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        return try IOBufferArtifactSnapshot(directory)
    }

    private func stagedInputs(_ directory: URL, originals: Bool) throws -> (producer: [URL], consumer: URL, expected: Data, hashes: [String: String]) {
        let origin = fixtures()
        let provenance = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            origin.appendingPathComponent("reference-provenance.json"))) as? [String: Any])
        try #require(provenance["status"] as? String == "JVM_DISTINCT_BOUNDARY_REFERENCE_AND_EXISTING_ORIGINAL45_REFERENCE;CANDIDATE_NOT_RUN")
        let pins = try #require(provenance["source_hashes"] as? [String: String])
        let sources = originals
            ? ["Originals/CommonBufferTest.kt", "Originals/AlwaysSharedCopyTrackerTest.kt", "Originals/MockSink.kt",
               "Originals/ScopedBufferHelpers.kt", "Originals/OriginalBufferDriver.kt"]
            : ["BufferBoundaries.kt"]
        let consumerName = originals ? "OriginalConsumer.kt" : "Consumer.kt"
        var producer: [URL] = []
        var hashes: [String: String] = [:]
        for name in sources + [consumerName] {
            let data = try Data(contentsOf: origin.appendingPathComponent(name))
            try #require(pins[name] == FileFingerprint.sha256Hex(data))
            let output = directory.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
            try data.write(to: output)
            hashes[output.path] = FileFingerprint.sha256Hex(data)
            if name != consumerName { producer.append(output) }
        }
        let consumer = directory.appendingPathComponent(consumerName)
        let expectedName = originals ? "original-reference-derived.stdout" : "reference.stdout"
        let expected = try Data(contentsOf: origin.appendingPathComponent(expectedName))
        let expectedHash = originals ? "original_expected_sha256" : "expected_sha256"
        try #require(provenance[expectedHash] as? String == FileFingerprint.sha256Hex(expected))
        try #require(expected.split(separator: 10).count == (originals ? 90 : 61))
        if originals {
            let ids = try #require(provenance["original_IDs"] as? [String])
            try #require(ids.count == 45 && Set(ids).count == 45)
            try #require(provenance["original_expected_output_is_derived_not_new_raw_execution"] as? Bool == true)
            try #require(provenance["existing_original_JVM_and_Native_Linux_reference_PASS"] as? Int == 45)
        }
        return (producer, consumer, expected, hashes)
    }

    @Test(arguments: [false, true], [0, 2])
    func publicBoundariesAndContextGettersExecuteInSourceAndLibrary(libraryMode: Bool, optimization: Int) throws {
        try run(libraryMode: libraryMode, optimization: optimization, producerLibrary: false, originals: false)
    }

    @Test(arguments: [0, 2])
    func actualBoundaryProducerAndIndependentConsumerKeepTheContract(optimization: Int) throws {
        try run(libraryMode: true, optimization: optimization, producerLibrary: true, originals: false)
    }

    @Test(arguments: [false, true], [0, 2])
    func originalFortyFiveKeepTheirBodiesAndPerIDResults(libraryMode: Bool, optimization: Int) throws {
        try run(libraryMode: libraryMode, optimization: optimization, producerLibrary: false, originals: true)
    }

    @Test(arguments: [0, 2])
    func actualOriginalTestProducerRunsFromIndependentConsumer(optimization: Int) throws {
        try run(libraryMode: true, optimization: optimization, producerLibrary: true, originals: true)
    }

    private func run(libraryMode: Bool, optimization: Int, producerLibrary: Bool, originals: Bool) throws {
        let entry = originals ? "kuu1729originalconsumer.main" : "kuu1729consumer.main"
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try library(libraryMode)
        defer { stdlib?.expectUnchanged() }
        let sourceManifest = BundledStdlib.manifestHash()
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        print("KUU1729_RUNTIME_DIRECTORY \(directory.path)")
        let staged = try stagedInputs(directory, originals: originals)
        var producer: IOBufferArtifactSnapshot?
        if producerLibrary {
            let base = directory.appendingPathComponent("buffer-contracts")
            let options = CompilerOptions(
                moduleName: "KUU1729ContractProducer", inputs: staged.producer.map(\.path), outputPath: base.path,
                emit: .library, target: TargetTriple.hostDefault(), optLevel: level,
                stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false
            )
            try #require(!options.inputs.contains(staged.consumer.path))
            try #require(!options.includeStdlib && options.stdlibLibraryPath == stdlib?.directory.path)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "Actual buffering fixture producer")
            let artifact = base.appendingPathExtension("kklib")
            let manifest = try #require(JSONSerialization.jsonObject(
                with: Data(contentsOf: artifact.appendingPathComponent("manifest.json"))
            ) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KUU1729ContractProducer")
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
            let objects = try #require(manifest["objects"] as? [String])
            try #require(!objects.isEmpty)
            for object in objects { try #require(!Data(contentsOf: artifact.appendingPathComponent(object)).isEmpty) }
            let records = MetadataDecoder().decode(try String(contentsOf: artifact.appendingPathComponent("metadata.bin"), encoding: .utf8))
            for fqName in [originals ? "kuu1729originals.main" : "kuu1729producer.runBufferBoundaries"] {
                try #require(records.contains { $0.kind == .function && $0.fqName == fqName && $0.visibility == .public })
            }
            producer = try IOBufferArtifactSnapshot(artifact)
        }
        var successfulChecksFinished = false
        defer {
            // The producer is removed by owned successful cleanup below.
            // Failed compile/run/check paths retain it and still check its hashes.
            if !successfulChecksFinished { producer?.expectUnchanged() }
        }
        let inputPaths = producerLibrary ? [staged.consumer.path] : staged.producer.map(\.path) + [staged.consumer.path]
        let searchPaths = producer.map { [$0.directory.path] } ?? []
        let executable = directory.appendingPathComponent("contract")
        let options = CompilerOptions(
            moduleName: "KUU1729BufferingConsumer", inputs: inputPaths, outputPath: executable.path,
            emit: .executable, searchPaths: searchPaths, target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false, entryPointFQName: entry
        )
        try #require(options.inputs == inputPaths && options.searchPaths == searchPaths)
        try #require(options.entryPointFQName == entry && options.optLevel == level)
        try #require(options.stdlibLibraryPath == stdlib?.directory.path && options.includeStdlib == !libraryMode)
        if producerLibrary { try #require(staged.producer.allSatisfy { !options.inputs.contains($0.path) }) }
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "Explicit compound consumer entry")
        try #require(files.isExecutableFile(atPath: executable.path))
        let executableHash = FileFingerprint.sha256Hex(try Data(contentsOf: executable))
        let receiptRoot = ProcessInfo.processInfo.environment["KSWIFTK_IO1729_RECEIPT_DIRECTORY"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? files.temporaryDirectory.appendingPathComponent("KUU1729-runtime-receipts", isDirectory: true)
        try files.createDirectory(at: receiptRoot, withIntermediateDirectories: true)
        let receiptBase = receiptRoot.appendingPathComponent(directory.lastPathComponent)
        let result = try io1729RunKeepingFailureEvidence(
            executable: executable, arguments: [], timeout: 30, receiptBase: receiptBase
        )
        try Data(result.stdout.utf8).write(to: receiptBase.appendingPathExtension("stdout"))
        try Data(result.stderr.utf8).write(to: receiptBase.appendingPathExtension("stderr"))
        try #require(result.exitCode == 0, "\(result.stderr)")
        try #require(result.stderr.isEmpty)
        try #require(Data(result.stdout.utf8) == staged.expected)
        for (path, hash) in staged.hashes { try #require(FileFingerprint.sha256Hex(Data(contentsOf: URL(fileURLWithPath: path))) == hash) }
        try stdlib?.requireUnchanged()
        try producer?.requireUnchanged()
        try #require(BundledStdlib.manifestHash() == sourceManifest)
        successfulChecksFinished = true
        // Failures preserve the entire UUID directory. Successes retain raw
        // output and all generated hashes before removing only owned artifacts.
        try io1729CleanupSuccessful(
            directory: directory, executable: executable, executableHash: executableHash,
            receiptBase: receiptBase, stdout: Data(result.stdout.utf8), expected: staged.expected,
            lane: (producerLibrary ? "producer-consumer" : libraryMode ? "stdlib-library" : "source") + (originals ? "-original45" : "-boundary61") + "-O\(optimization)",
            stdlib: stdlib, producer: producer, sourceManifest: sourceManifest, inputPaths: inputPaths, entry: entry
        )
    }
}

private struct IOBufferArtifactSnapshot {
    let directory: URL
    let hashes: [String: String]
    init(_ directory: URL) throws {
        self.directory = directory
        hashes = try io1729ArtifactHashes(directory)
        try #require(hashes["manifest.json"] != nil && hashes["metadata.bin"] != nil)
        print("KUU1729_ARTIFACT \(directory.path) files=\(hashes.count)")
    }
    func requireUnchanged() throws { try #require(io1729ArtifactHashes(directory) == hashes) }
    func expectUnchanged() { #expect((try? io1729ArtifactHashes(directory)) == hashes) }
}

private func io1729ArtifactHashes(_ directory: URL) throws -> [String: String] {
    let canonical = directory.standardizedFileURL
    let enumerator = try #require(FileManager.default.enumerator(at: canonical, includingPropertiesForKeys: [.isRegularFileKey]))
    var hashes: [String: String] = [:]
    for case let file as URL in enumerator {
        guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
        hashes[String(file.path.dropFirst(canonical.path.count + 1))] = FileFingerprint.sha256Hex(try Data(contentsOf: file))
    }
    return hashes
}

// Same ownership/proof-before-cleanup policy as the staged KUU1767 helper;
// actual timeout is 30s here and raw stdout/stderr remain outside the UUID tree.
private func io1729CleanupSuccessful(
    directory: URL, executable: URL, executableHash: String, receiptBase: URL,
    stdout: Data, expected: Data, lane: String, stdlib: IOBufferArtifactSnapshot?,
    producer: IOBufferArtifactSnapshot?, sourceManifest: String, inputPaths: [String], entry: String
) throws {
    let files = FileManager.default
    let owned = directory.standardizedFileURL
    try #require(owned.deletingLastPathComponent() == files.temporaryDirectory.standardizedFileURL)
    try #require(UUID(uuidString: owned.lastPathComponent) != nil)
    try #require(!receiptBase.standardizedFileURL.path.hasPrefix(owned.path + "/"))
    try #require(FileFingerprint.sha256Hex(Data(contentsOf: executable)) == executableHash)
    let hashes = try io1729ArtifactHashes(owned)
    var sizes: [String: Int] = [:]
    for name in hashes.keys { sizes[name] = try Data(contentsOf: owned.appendingPathComponent(name)).count }
    var proof: [String: Any] = [
        "status": "PASS_PROOF_BEFORE_CLEANUP", "lane": lane, "owned_directory": owned.path,
        "native_returned_after_exit": true, "actual_exit": 0, "runtime_timeout_seconds": 30,
        "entryPointFQName": entry, "inputs": inputPaths, "source_manifest": sourceManifest,
        "stdout_exact": true, "stderr_empty": true, "stdout_sha256": FileFingerprint.sha256Hex(stdout),
        "expected_sha256": FileFingerprint.sha256Hex(expected), "executable_sha256_before_after": executableHash,
        "generated_files_sha256": hashes, "generated_files_bytes": sizes,
        "generated_bytes_before_cleanup": sizes.values.reduce(0, +),
        "free_bytes_before_cleanup": try #require(files.attributesOfFileSystem(forPath: owned.path)[.systemFreeSize] as? NSNumber).uint64Value,
        "stdlib_path": stdlib?.directory.path ?? "SOURCE", "stdlib_full_hashes": stdlib?.hashes ?? [:],
        "producer_path": producer?.directory.path ?? "NONE", "producer_full_hashes": producer?.hashes ?? [:]
    ]
    let receipt = receiptBase.appendingPathExtension("json")
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]).write(to: receipt, options: .atomic)
    try files.removeItem(at: owned)
    try #require(!files.fileExists(atPath: owned.path))
    proof["status"] = "PASS_CLEANED"
    proof["free_bytes_after_cleanup"] = try #require(files.attributesOfFileSystem(forPath: receiptBase.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber).uint64Value
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]).write(to: receipt, options: .atomic)
    print("KUU1729_RUNTIME_RECEIPT \(receipt.path)")
}

// CommandRunner throws before returning a non-zero result. Save the result's
// exact String-to-UTF8 representation before rethrowing the original error.
// For timeout/launch errors its API exposes only a formatted diagnostic,
// not original process bytes, PID/SID or a trustworthy final exit status.
private func io1729RunKeepingFailureEvidence(
    executable: URL, arguments: [String], timeout: TimeInterval, receiptBase: URL
) throws -> CommandResult {
    let start = Date()
    do {
        return try CommandRunner.run(executable: executable.path, arguments: arguments, timeout: timeout)
    } catch {
        let runError = error
        var proof: [String: Any] = [
            "argv": [executable.path] + arguments, "requested_timeout_seconds": timeout,
            "started_utc": ISO8601DateFormatter().string(from: start),
            "finished_utc": ISO8601DateFormatter().string(from: Date()),
            "elapsed_seconds": Date().timeIntervalSince(start),
            "actual_exit": NSNull(), "generated_UUID_retained": true,
            "PID_SID_PGID": "NOT_EXPOSED_BY_COMMANDRUNNER", "original_error_rethrown": true,
            "output_encoding": "CommandResult String encoded as UTF-8; runner may replace invalid input UTF-8"
        ]
        do {
            if case let CommandRunnerError.nonZeroExit(failed) = runError {
                let stdout = Data(failed.stdout.utf8)
                let stderr = Data(failed.stderr.utf8)
                try stdout.write(to: receiptBase.appendingPathExtension("stdout"))
                try stderr.write(to: receiptBase.appendingPathExtension("stderr"))
                proof["status"] = "NATIVE_NONZERO_EXIT_RETAINED"
                proof["actual_exit"] = failed.exitCode
                proof["CommandResult_output_preserved_without_trimming"] = true
                proof["stdout_sha256"] = FileFingerprint.sha256Hex(stdout)
                proof["stderr_sha256"] = FileFingerprint.sha256Hex(stderr)
                proof["stdout_bytes"] = stdout.count
                proof["stderr_bytes"] = stderr.count
            } else {
                let message: String
                if case let CommandRunnerError.timedOut(value) = runError {
                    proof["status"] = "RUNNER_TIMEOUT_OR_DRAIN_TIMEOUT"
                    message = value
                } else if case let CommandRunnerError.launchFailed(value) = runError {
                    proof["status"] = "RUNNER_LAUNCH_FAILED"
                    message = value
                } else {
                    proof["status"] = "RUNNER_ERROR"
                    message = String(describing: runError)
                }
                proof["original_stdout_stderr_bytes_available"] = false
                proof["diagnostic_message_is_not_raw_process_output"] = true
                try Data(message.utf8).write(to: receiptBase.appendingPathExtension("runner-error.txt"))
            }
            try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
                .write(to: receiptBase.appendingPathExtension("failure.json"), options: .atomic)
        } catch {
            // Receipt IO failure must not replace the native/runner failure.
            Issue.record("Unable to persist KUU1729 failure evidence: \(error)")
        }
        throw runError
    }
}

@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct IOFileFamilyExecutionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func artifact() throws -> IOFileFamilyArtifactSnapshot {
        let path = try testStdlibArtifactPath()
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try io1761RequireLibrary(directory, moduleName: "KSwiftKStdlib")
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            directory.appendingPathComponent("manifest.json"))) as? [String: Any])
        try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        return try IOFileFamilyArtifactSnapshot(directory)
    }

    private func compile(inputs: [String], output: String, emit: EmitMode = .executable,
                         stdlib: IOFileFamilyArtifactSnapshot?, optimization: Int,
                         searchPaths: [String] = [], moduleName: String = "KUU1761Files") throws {
        let entry: String?
        if case .executable = emit { entry = "main" } else { entry = nil }
        let options = CompilerOptions(moduleName: moduleName, inputs: inputs, outputPath: output,
                                      emit: emit, searchPaths: searchPaths, target: defaultTargetTriple(),
                                      optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                                      stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false,
                                      entryPointFQName: entry)
        try #require(options.inputs == inputs && options.searchPaths == searchPaths)
        try #require(options.stdlibLibraryPath == stdlib?.directory.path && !options.allowDefaultStdlibLibrary)
        try #require(options.includeStdlib == (stdlib == nil) && options.entryPointFQName == entry)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
    }

    private func receiptBase(_ root: URL) throws -> URL {
        let fm = FileManager.default
        let receipts = ProcessInfo.processInfo.environment["KSWIFTK_IO1761_RECEIPT_DIRECTORY"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fm.temporaryDirectory.appendingPathComponent("KUU1761-runtime-receipts", isDirectory: true)
        try fm.createDirectory(at: receipts, withIntermediateDirectories: true)
        return receipts.appendingPathComponent(root.lastPathComponent)
    }

    private func executeAndKeepProof(root: URL, binary: URL, expected: Data, inputs: [String],
                                     inputHashes: [String: String], sourceManifest: String,
                                     stdlib: IOFileFamilyArtifactSnapshot?, producer: IOFileFamilyArtifactSnapshot? = nil,
                                     lane: String, timeout: TimeInterval = 30) throws {
        let fm = FileManager.default
        try #require(fm.isExecutableFile(atPath: binary.path))
        let binaryHash = FileFingerprint.sha256Hex(try Data(contentsOf: binary))
        let receipt = try receiptBase(root)
        let result = try io1761RunKeepingFailureEvidence(binary: binary, directory: root,
                                                       timeout: timeout, receiptBase: receipt)
        let stdout = Data(result.stdout.utf8)
        let stderr = Data(result.stderr.utf8)
        try stdout.write(to: receipt.appendingPathExtension("stdout"))
        try stderr.write(to: receipt.appendingPathExtension("stderr"))
        try #require(result.exitCode == 0 && stderr.isEmpty)
        try #require(stdout == expected, "\(result.stdout.debugDescription)")
        for (path, hash) in inputHashes { try #require(FileFingerprint.sha256Hex(Data(contentsOf: URL(fileURLWithPath: path))) == hash) }
        try #require(BundledStdlib.manifestHash() == sourceManifest)
        try stdlib?.requireUnchanged()
        try producer?.requireUnchanged()
        try io1761CleanupSuccessful(directory: root, binary: binary, binaryHash: binaryHash,
                                    receiptBase: receipt, stdout: stdout, expected: expected,
                                    inputPaths: inputs, inputHashes: inputHashes, sourceManifest: sourceManifest,
                                    stdlib: stdlib, producer: producer, lane: lane, timeout: timeout)
    }

    @Test(arguments: [false, true], [0, 2])
    func supplementalAPIAndLifecycleContracts(library: Bool, optimization: Int) throws {
        let stdlib = library ? try artifact() : nil
        defer { stdlib?.expectUnchanged() }
        let sourceManifest = BundledStdlib.manifestHash()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        print("KUU1761_RUNTIME_DIRECTORY \(root.path)")
        let fixtures = ["Scripts/diff_cases/kotlinx_io_file_api_supplements.kt",
                        "Scripts/diff_cases/kotlinx_io_file_lifecycle_contracts.kt",
                        "Scripts/diff_cases/kotlinx_io_file_legacy_suppressed.kt",
                        "Scripts/kotlinx_io_upstream/files/PosixAdapterControls.kt"]
        var paths: [String] = []
        var expected = ""
        for (index, relative) in fixtures.enumerated() {
            let original = try String(contentsOf: repository.appendingPathComponent(relative), encoding: .utf8)
            // Package insertion follows an existing @file directive and preserves all original bytes.
            let prefixEnd = original.hasPrefix("@file:") ? try #require(original.firstIndex(of: "\n")) : original.startIndex
            let insertion = original.hasPrefix("@file:") ? original.index(after: prefixEnd) : prefixEnd
            let packaged = String(original[..<insertion]) + "package b06fixture\(index)\n\n" + String(original[insertion...])
            try #require(packaged.replacingOccurrences(of: "package b06fixture\(index)\n\n", with: "") == original)
            let path = root.appendingPathComponent("Fixture\(index).kt")
            try packaged.write(to: path, atomically: true, encoding: .utf8)
            paths.append(path.path)
            expected += try String(contentsOf: repository.appendingPathComponent(relative).deletingPathExtension()
                                       .appendingPathExtension("expected"), encoding: .utf8)
        }
        try #require(expected.split(separator: "\n").count == 33)
        let driver = root.appendingPathComponent("Driver.kt")
        try "fun main() { b06fixture0.main(); b06fixture1.main(); b06fixture2.main(); b06fixture3.main() }\n"
            .write(to: driver, atomically: true, encoding: .utf8)
        paths.append(driver.path)
        paths.append(repository.appendingPathComponent("Scripts/kotlinx_io_upstream/support/PosixFileExistenceTestAdapter.kt").path)
        let binary = root.appendingPathComponent("candidate")
        let hashes = try io1761InputHashes(paths)
        try compile(inputs: paths, output: binary.path, stdlib: stdlib, optimization: optimization)
        try executeAndKeepProof(root: root, binary: binary, expected: Data(expected.utf8), inputs: paths,
                                inputHashes: hashes, sourceManifest: sourceManifest, stdlib: stdlib,
                                lane: "supplement33-" + (library ? "library" : "source") + "-O\(optimization)")
    }

    @Test(arguments: [false, true], [0, 2])
    func closedRawFilesFollowTheCommonSafetyContract(library: Bool, optimization: Int) throws {
        let stdlib = library ? try artifact() : nil
        defer { stdlib?.expectUnchanged() }
        let sourceManifest = BundledStdlib.manifestHash()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        print("KUU1761_RUNTIME_DIRECTORY \(root.path)")
        let source = try Data(contentsOf: repository.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/IOFileFamily/closed-common-contract/fixture.kt"))
        let expected = try Data(contentsOf: repository.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/IOFileFamily/closed-common-contract/expected.stdout"))
        try #require(FileFingerprint.sha256Hex(source) == "9d9aaec64af3b095b7b7c5dedd5f1eee5ce765085ee1b5102fe6434bd7507b04")
        try #require(FileFingerprint.sha256Hex(expected) == "d641638b89b1806fad4ee6678bdde525bb8ff4d85e517ceb88309f307db5bdaa")
        try #require(String(decoding: expected, as: UTF8.self).split(separator: "\n").count == 5)
        let input = root.appendingPathComponent("Closed.kt")
        try source.write(to: input)
        // executeAndKeepProof checks this input hash before successful owned cleanup.
        let binary = root.appendingPathComponent("candidate")
        let hashes = try io1761InputHashes([input.path])
        try compile(inputs: [input.path], output: binary.path, stdlib: stdlib, optimization: optimization)
        try executeAndKeepProof(root: root, binary: binary, expected: expected, inputs: [input.path],
                                inputHashes: hashes, sourceManifest: sourceManifest, stdlib: stdlib,
                                lane: "closed-common5-" + (library ? "library" : "source") + "-O\(optimization)", timeout: 10)
    }

    @Test(arguments: [0, 2])
    func defaultsVarargsAndFileSystemValueCrossProducerConsumer(optimization: Int) throws {
        let stdlib = try artifact()
        defer { stdlib.expectUnchanged() }
        let sourceManifest = BundledStdlib.manifestHash()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        print("KUU1761_RUNTIME_DIRECTORY \(root.path)")
        let producer = root.appendingPathComponent("Producer.kt")
        try """
        package b06producer
        import kotlinx.io.files.*
        public fun metadata(regular: Boolean = false, directory: Boolean = false, size: Long = 0L): FileMetadata =
            FileMetadata(isRegularFile = regular, isDirectory = directory, size = size)
        public fun joined(base: Path, vararg parts: String): Path = Path(base, *parts)
        public fun fileSystem(): FileSystem = SystemFileSystem
        public fun separator(): Char = SystemPathSeparator
        """.write(to: producer, atomically: true, encoding: .utf8)
        var inputHashes = try io1761InputHashes([producer.path])
        let output = root.appendingPathComponent("Producer")
        try compile(inputs: [producer.path], output: output.path, emit: .library, stdlib: stdlib, optimization: optimization,
                    moduleName: "KUU1761FilesProducer")
        let library = output.appendingPathExtension("kklib")
        try io1761RequireLibrary(library, moduleName: "KUU1761FilesProducer")
        let metadata = MetadataDecoder().decode(try String(contentsOf: library.appendingPathComponent("metadata.bin"), encoding: .utf8))
        for name in ["metadata", "joined", "fileSystem", "separator"] {
            try #require(metadata.contains { $0.kind == .function && $0.fqName == "b06producer." + name && $0.visibility == .public })
        }
        let defaults = try #require(metadata.first { $0.fqName == "b06producer.metadata" && $0.kind == .function })
        try #require(defaults.valueParameterHasDefaultValues == [true, true, true])
        let joined = try #require(metadata.first { $0.fqName == "b06producer.joined" && $0.kind == .function })
        try #require(joined.valueParameterIsVararg == [false, true])
        let producerSnapshot = try IOFileFamilyArtifactSnapshot(library)
        let consumer = root.appendingPathComponent("Consumer.kt")
        try """
        import b06producer.*
        import kotlinx.io.files.*
        fun main() {
            val a = metadata()
            println("metadata:${a.isRegularFile}:${a.isDirectory}:${a.size}")
            val b = metadata(size = 7L, regular = true)
            println("metadata:${b.isRegularFile}:${b.isDirectory}:${b.size}")
            println("joined:${joined(Path("a"), *arrayOf("b", "c"))}")
            println("empty:${joined(Path("a"))}")
            val fs: FileSystem = fileSystem()
            println("identity:${fs === SystemFileSystem}")
            println("separator:${separator()}")
        }
        """.write(to: consumer, atomically: true, encoding: .utf8)
        let binary = root.appendingPathComponent("candidate")
        // The producer Kotlin file is deliberately absent from consumer inputs.
        inputHashes.merge(try io1761InputHashes([consumer.path])) { original, _ in original }
        try #require(consumer.path != producer.path)
        try compile(inputs: [consumer.path], output: binary.path, stdlib: stdlib, optimization: optimization,
                    searchPaths: [library.path], moduleName: "KUU1761FilesConsumer")
        let expected = Data("metadata:false:false:0\nmetadata:true:false:7\njoined:a/b/c\nempty:a\nidentity:true\nseparator:/\n".utf8)
        try executeAndKeepProof(root: root, binary: binary, expected: expected, inputs: [consumer.path],
                                inputHashes: inputHashes, sourceManifest: sourceManifest, stdlib: stdlib,
                                producer: producerSnapshot, lane: "producer-consumer6-O\(optimization)")
    }
}

private struct IOFileFamilyArtifactSnapshot {
    let directory: URL
    let hashes: [String: String]
    init(_ directory: URL) throws {
        self.directory = directory
        hashes = try io1761ArtifactHashes(directory)
        try #require(hashes["manifest.json"] != nil && hashes["metadata.bin"] != nil)
    }
    func requireUnchanged() throws { try #require(io1761ArtifactHashes(directory) == hashes) }
    func expectUnchanged() { #expect((try? io1761ArtifactHashes(directory)) == hashes) }
}

private func io1761InputHashes(_ paths: [String]) throws -> [String: String] {
    var hashes: [String: String] = [:]
    for path in paths { hashes[path] = FileFingerprint.sha256Hex(try Data(contentsOf: URL(fileURLWithPath: path))) }
    return hashes
}

private func io1761ArtifactHashes(_ directory: URL) throws -> [String: String] {
    let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
    let enumerator = try #require(FileManager.default.enumerator(at: canonical, includingPropertiesForKeys: [.isRegularFileKey]))
    var hashes: [String: String] = [:]
    for case let file as URL in enumerator {
        guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
        hashes[String(file.path.dropFirst(canonical.path.count + 1))] = FileFingerprint.sha256Hex(try Data(contentsOf: file))
    }
    return hashes
}

private func io1761RequireLibrary(_ directory: URL, moduleName: String) throws {
    let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        directory.appendingPathComponent("manifest.json"))) as? [String: Any])
    try #require(manifest["moduleName"] as? String == moduleName)
    try #require(manifest["formatVersion"] as? Int == 1)
    try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
    let objects = try #require(manifest["objects"] as? [String])
    try #require(!objects.isEmpty)
    for object in objects { try #require(!Data(contentsOf: directory.appendingPathComponent(object)).isEmpty) }
}

private func io1761RunKeepingFailureEvidence(binary: URL, directory: URL, timeout: TimeInterval,
                                            receiptBase: URL) throws -> CommandResult {
    let started = Date()
    do {
        return try CommandRunner.run(executable: binary.path, arguments: [], currentDirectoryPath: directory.path,
                                     timeout: timeout)
    } catch {
        let original = error
        var proof: [String: Any] = [
            "argv": [binary.path], "cwd": directory.path, "requested_timeout_seconds": timeout,
            "started_utc": ISO8601DateFormatter().string(from: started),
            "finished_utc": ISO8601DateFormatter().string(from: Date()),
            "elapsed_seconds": Date().timeIntervalSince(started), "actual_exit": NSNull(),
            "generated_UUID_retained": true, "original_error_rethrown": true,
            "PID_SID_PGID": "NOT_EXPOSED_BY_COMMANDRUNNER",
            "output_encoding": "CommandResult String encoded as UTF-8; invalid original UTF-8 may already be replaced"
        ]
        do {
            if case let CommandRunnerError.nonZeroExit(result) = original {
                let stdout = Data(result.stdout.utf8)
                let stderr = Data(result.stderr.utf8)
                try stdout.write(to: receiptBase.appendingPathExtension("stdout"))
                try stderr.write(to: receiptBase.appendingPathExtension("stderr"))
                proof["status"] = "NATIVE_NONZERO_EXIT_RETAINED"
                proof["actual_exit"] = result.exitCode
                proof["CommandResult_output_preserved_without_trimming"] = true
                proof["stdout_sha256"] = FileFingerprint.sha256Hex(stdout)
                proof["stderr_sha256"] = FileFingerprint.sha256Hex(stderr)
                proof["stdout_bytes"] = stdout.count
                proof["stderr_bytes"] = stderr.count
            } else {
                let message: String
                if case let CommandRunnerError.timedOut(value) = original {
                    proof["status"] = "RUNNER_TIMEOUT_OR_DRAIN_TIMEOUT"
                    message = value
                } else if case let CommandRunnerError.launchFailed(value) = original {
                    proof["status"] = "RUNNER_LAUNCH_FAILED"
                    message = value
                } else {
                    proof["status"] = "RUNNER_ERROR"
                    message = String(describing: original)
                }
                proof["original_stdout_stderr_bytes_available"] = false
                proof["diagnostic_message_is_not_raw_process_output"] = true
                try Data(message.utf8).write(to: receiptBase.appendingPathExtension("runner-error.txt"))
            }
            try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
                .write(to: receiptBase.appendingPathExtension("failure.json"), options: .atomic)
        } catch {
            Issue.record("Unable to persist KUU1761 failure evidence: \(error)")
        }
        throw original
    }
}

private func io1761CleanupSuccessful(directory: URL, binary: URL, binaryHash: String, receiptBase: URL,
                                     stdout: Data, expected: Data, inputPaths: [String], inputHashes: [String: String],
                                     sourceManifest: String, stdlib: IOFileFamilyArtifactSnapshot?,
                                     producer: IOFileFamilyArtifactSnapshot?, lane: String, timeout: TimeInterval) throws {
    let fm = FileManager.default
    let owned = directory.standardizedFileURL
    try #require(owned.deletingLastPathComponent() == fm.temporaryDirectory.standardizedFileURL)
    try #require(UUID(uuidString: owned.lastPathComponent) != nil)
    try #require(!receiptBase.standardizedFileURL.path.hasPrefix(owned.path + "/"))
    try #require(FileFingerprint.sha256Hex(Data(contentsOf: binary)) == binaryHash)
    let hashes = try io1761ArtifactHashes(owned)
    var sizes: [String: Int] = [:]
    for name in hashes.keys { sizes[name] = try Data(contentsOf: owned.appendingPathComponent(name)).count }
    var proof: [String: Any] = [
        "status": "PASS_PROOF_BEFORE_CLEANUP", "lane": lane, "owned_directory": owned.path,
        "native_returned_after_exit": true, "actual_exit": 0, "runtime_timeout_seconds": timeout,
        "entryPointFQName": "main", "compiler_inputs": inputPaths, "staged_input_hashes": inputHashes,
        "source_manifest": sourceManifest, "stdout_exact": true, "stderr_empty": true,
        "stdout_sha256": FileFingerprint.sha256Hex(stdout), "expected_sha256": FileFingerprint.sha256Hex(expected),
        "executable_sha256_before_after": binaryHash, "generated_files_sha256": hashes, "generated_files_bytes": sizes,
        "generated_bytes_before_cleanup": sizes.values.reduce(0, +),
        "stdlib_path": stdlib?.directory.path ?? "SOURCE", "stdlib_full_hashes": stdlib?.hashes ?? [:],
        "producer_path": producer?.directory.path ?? "NONE", "producer_full_hashes": producer?.hashes ?? [:],
        "free_bytes_before_cleanup": try #require(fm.attributesOfFileSystem(forPath: owned.path)[.systemFreeSize] as? NSNumber).uint64Value
    ]
    let receipt = receiptBase.appendingPathExtension("json")
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
        .write(to: receipt, options: .atomic)
    try fm.removeItem(at: owned)
    try #require(!fm.fileExists(atPath: owned.path))
    proof["status"] = "PASS_CLEANED"
    proof["free_bytes_after_cleanup"] = try #require(fm.attributesOfFileSystem(forPath: receiptBase.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber).uint64Value
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
        .write(to: receipt, options: .atomic)
    print("KUU1761_RUNTIME_RECEIPT \(receipt.path)")
}

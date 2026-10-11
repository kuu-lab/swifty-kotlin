@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testJVMInteropNioReferenceBehavior(useProducerLibrary: Bool, optimization: Int) throws {
        let level: OptimizationLevel = optimization == 2 ? .O2 : .O0
        try runJVMInteropNioFixture("native156", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "b284b962aa302b6db6e2a5be925cc16a1561fd7232b53dc35e4b3d66357d9d31", consumerHash: "a4148c6628f584782ad6d0d14a4993055fa8707fb1fe6e94fc5bdfd6e8251292", expectedHash: "b5665907768289a01b6f5982167738d0dc03a5f469c9212439b85c70a97a6b53")
    }

    @Test(arguments: [false, true], [0, 2])
    func testJVMInteropOriginalFileChannelProducers(useProducerLibrary: Bool, optimization: Int) throws {
        let level: OptimizationLevel = optimization == 2 ? .O2 : .O0
        try runJVMInteropNioFixture("filechannel12", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "e5959b55df61c9a021336c98a46dc4e60277a223b5ffad285123e25275324cc1", consumerHash: "1728ea2963f5c6e3065f827e578c1bc5a8a3e91a457c5cce0d740056a4e53945", expectedHash: "6e8f76b0001779b41b22038f10f3f16ab74a765d74eaf9685c0877c66378cfd8",
            fixtureDirectory: "JVMInteropFileChannel")
    }

    private func runJVMInteropNioFixture(
        _ fixture: String, useProducerLibrary: Bool, level: OptimizationLevel,
        producerHash: String, consumerHash: String, expectedHash: String, fixtureDirectory: String = "JVMInteropNio"
    ) throws {
        let fixtures = jvmInteropNioRepositoryRoot().appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/" + fixtureDirectory, isDirectory: true)
        let producer = try Data(contentsOf: fixtures.appendingPathComponent("producer.kt"))
        let consumer = try Data(contentsOf: fixtures.appendingPathComponent("consumer.kt"))
        let expected = try Data(contentsOf: fixtures.appendingPathComponent("expected.stdout"))
        try #require(FileFingerprint.sha256Hex(producer) == producerHash)
        try #require(FileFingerprint.sha256Hex(consumer) == consumerHash)
        try #require(FileFingerprint.sha256Hex(expected) == expectedHash)
        let stdlib = try jvmInteropNioStdlibSnapshot(required: useProducerLibrary)
        defer { stdlib?.expectUnchanged() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let durableRoot = ProcessInfo.processInfo.environment["KSWIFTK_IO1762_EVIDENCE_DIRECTORY"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("kswiftk-kuu1762-evidence", isDirectory: true)
        var completedProof = false
        defer {
            if completedProof {
                try? FileManager.default.removeItem(at: directory)
            } else {
                // Input/library defers were registered later and run first.
                // Keep the entire failed UUID under the caller's collection root.
                let destination = durableRoot.appendingPathComponent("failed-" + directory.lastPathComponent, isDirectory: true)
                let before = try? jvmInteropNioArtifactHashes(directory)
                var actualPath = directory.path
                var moveError: String?
                do {
                    try FileManager.default.createDirectory(at: durableRoot, withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: directory, to: destination)
                    actualPath = destination.path
                } catch { moveError = String(describing: error) }
                let after = try? jvmInteropNioArtifactHashes(URL(fileURLWithPath: actualPath, isDirectory: true))
                let evidence: [String: Any] = [
                    "status": "FAILED_OR_INCOMPLETE_PROOF_RETAINED",
                    "original_directory": directory.path, "actual_directory": actualPath,
                    "requested_collection_root": durableRoot.path,
                    "full_file_sha256_before_move": before as Any? ?? NSNull(),
                    "full_file_sha256_after_move": after as Any? ?? NSNull(),
                    "full_file_set_and_bytes_preserved": before != nil && before == after,
                    "move_error": moveError as Any? ?? NSNull(),
                    "input_artifact_and_executable_cleanup": false,
                    "owned_descendant_reap": "MUST_BE_OBSERVED_BY_OUTER_GATE",
                ]
                if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys, .prettyPrinted]) {
                    try? data.write(to: URL(fileURLWithPath: actualPath, isDirectory: true).appendingPathComponent("failure-preservation.json"))
                    try? data.write(to: durableRoot.appendingPathComponent("failed-" + directory.lastPathComponent + ".receipt.json"))
                }
                print("Retained failed fixture: " + actualPath)
                if let moveError { print("Failure archive move error; original retained when move failed: " + moveError) }
            }
        }
        let producerInput = directory.appendingPathComponent("producer.kt")
        let consumerInput = directory.appendingPathComponent("consumer.kt")
        try producer.write(to: producerInput)
        try consumer.write(to: consumerInput)
        defer {
            #expect((try? Data(contentsOf: producerInput)) == producer)
            #expect((try? Data(contentsOf: consumerInput)) == consumer)
        }
        let moduleName = "KUU1762Nio_" + fixture
        var library: JVMInteropNioArtifactSnapshot?
        defer { library?.expectUnchanged() }
        if useProducerLibrary {
            let base = directory.appendingPathComponent("producer")
            let options = CompilerOptions(
                moduleName: moduleName, inputs: [producerInput.path], outputPath: base.path,
                emit: .library, target: TargetTriple.hostDefault(), optLevel: level,
                stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false)
            try #require(options.inputs == [producerInput.path])
            try #require(!options.includeStdlib && !options.allowDefaultStdlibLibrary)
            try #require(options.stdlibLibraryPath == stdlib?.directory.path)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "JVM interoperability NIO producer")
            let artifact = base.appendingPathExtension("kklib")
            try jvmInteropNioRequireLibrary(artifact, moduleName: moduleName)
            library = try JVMInteropNioArtifactSnapshot(directory: artifact)
        }
        let executable = directory.appendingPathComponent("consumer")
        let inputs = useProducerLibrary ? [consumerInput.path] : [producerInput.path, consumerInput.path]
        let searchPaths = library.map { [$0.directory.path] } ?? []
        let options = CompilerOptions(
            moduleName: moduleName + "Consumer", inputs: inputs, outputPath: executable.path,
            emit: .executable, searchPaths: searchPaths, target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false)
        try #require(options.inputs == inputs && options.searchPaths == searchPaths)
        try #require(options.includeStdlib == !useProducerLibrary && !options.allowDefaultStdlibLibrary)
        try #require(options.stdlibLibraryPath == stdlib?.directory.path)
        if useProducerLibrary { try #require(!options.inputs.contains(producerInput.path)) }
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "JVM interoperability NIO consumer")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        let result: CommandResult
        do {
            result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
        } catch {
            if case let CommandRunnerError.nonZeroExit(failed) = error {
                try? Data(failed.stdout.utf8).write(to: directory.appendingPathComponent("run.stdout"))
                try? Data(failed.stderr.utf8).write(to: directory.appendingPathComponent("run.stderr"))
                try? Data(String(failed.exitCode).utf8).write(to: directory.appendingPathComponent("run.exit-code"))
            }
            // Timeout errors expose the existing CommandRunner description,
            // with trimmed captured output; do not label it complete raw data.
            try? Data(String(describing: error).utf8).write(to: directory.appendingPathComponent("run.error-description"))
            throw error
        }
        try Data(result.stdout.utf8).write(to: directory.appendingPathComponent("run.stdout"))
        try Data(result.stderr.utf8).write(to: directory.appendingPathComponent("run.stderr"))
        try #require(result.exitCode == 0, "\(result.stderr)")
        try #require(result.stderr.isEmpty)
        try #require(Data(result.stdout.utf8) == expected)
        try #require(try Data(contentsOf: producerInput) == producer)
        try #require(try Data(contentsOf: consumerInput) == consumer)
        if let library {
            try #require(try jvmInteropNioArtifactHashes(library.directory) == library.hashes)
        }
        if let stdlib {
            try #require(try jvmInteropNioArtifactHashes(stdlib.directory) == stdlib.hashes)
        }
        // Preserve successful evidence outside the UUID compilation directory
        // before allowing cleanup. CommandRunner output is UTF-8 decoded;
        // the retained outer runner owns raw bytes and descendant reap proof.
        let evidenceDirectory = durableRoot.appendingPathComponent(directory.lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        for (name, bytes) in [("producer.kt", producer), ("consumer.kt", consumer), ("expected.stdout", expected),
                              ("run.stdout.utf8", Data(result.stdout.utf8)), ("run.stderr.utf8", Data(result.stderr.utf8))] {
            try bytes.write(to: evidenceDirectory.appendingPathComponent(name))
        }
        let proof: [String: Any] = [
            "status": "PASS", "fixture": fixture, "expected_rows": expected.split(separator: 10).count,
            "source_or_library": useProducerLibrary ? "producer-library" : "source",
            "optimization": String(describing: level), "command_exit_code": result.exitCode,
            "stdout_exact_match": Data(result.stdout.utf8) == expected,
            "captured_output": "UTF-8-decoded CommandRunner capture; may be partial if draining failed",
            "raw_byte_and_descendant_reap_proof": "REQUIRED_FROM_RETAINED_OUTER_GATE",
            "producer_input_sha256": producerHash, "consumer_input_sha256": consumerHash, "expected_sha256": expectedHash,
            "executable_sha256": FileFingerprint.sha256Hex(try Data(contentsOf: executable)),
            "inputs": options.inputs, "search_paths": options.searchPaths,
            "include_stdlib": options.includeStdlib, "allow_default_stdlib_library": options.allowDefaultStdlibLibrary,
            "stdlib_library_path": options.stdlibLibraryPath as Any? ?? NSNull(),
            "producer_artifact_path": library?.directory.path as Any? ?? NSNull(),
            "producer_artifact_full_hashes": library?.hashes as Any? ?? NSNull(),
            "stdlib_artifact_full_hashes": stdlib?.hashes as Any? ?? NSNull(),
            "publication_stdlib_manifest_hash": BundledStdlib.manifestHash(),
        ]
        try JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys, .prettyPrinted])
            .write(to: evidenceDirectory.appendingPathComponent("success-proof.json"))
        print("Retained KUU1762 success evidence: " + evidenceDirectory.path)
        completedProof = true
    }
}

private func jvmInteropNioRepositoryRoot(file: StaticString = #filePath) -> URL {
    var root = URL(fileURLWithPath: String(describing: file))
    for _ in 0..<4 { root.deleteLastPathComponent() }
    return root
}

private struct JVMInteropNioArtifactSnapshot {
    let directory: URL
    let hashes: [String: String]
    init(directory: URL) throws {
        self.directory = directory
        hashes = try jvmInteropNioArtifactHashes(directory)
        try #require(hashes["manifest.json"] != nil && hashes["metadata.bin"] != nil)
    }
    func expectUnchanged() {
        #expect((try? jvmInteropNioArtifactHashes(directory)) == hashes,
                "Full producer artifact file set and SHA must remain unchanged")
    }
}

private func jvmInteropNioArtifactHashes(_ directory: URL) throws -> [String: String] {
    // Keep the root and enumerated child URLs on the same lexical path. Resolving
    // only the root turns macOS /private/tmp into /tmp while enumeration keeps
    // returning /private/tmp children, which corrupts every relative key.
    let root = directory.standardizedFileURL
    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
    var hashes: [String: String] = [:]
    for case let file as URL in enumerator {
        guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
        let filePath = file.standardizedFileURL.path
        try #require(filePath.hasPrefix(rootPrefix), "Artifact entry escaped producer library root")
        let relativePath = String(filePath.dropFirst(rootPrefix.count))
        hashes[relativePath] = FileFingerprint.sha256Hex(try Data(contentsOf: file))
    }
    return hashes
}

private func jvmInteropNioRequireLibrary(_ directory: URL, moduleName: String) throws {
    let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    try #require(manifest["moduleName"] as? String == moduleName)
    try #require(manifest["formatVersion"] as? Int == 1)
    try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
    let objects = try #require(manifest["objects"] as? [String])
    try #require(!objects.isEmpty)
    for object in objects { try #require(!(try Data(contentsOf: directory.appendingPathComponent(object))).isEmpty) }
}

private func jvmInteropNioStdlibSnapshot(required: Bool) throws -> JVMInteropNioArtifactSnapshot? {
    guard required else { return nil }
    TestStdlibCache.shared.prepare()
    let path = try #require(CompilerOptions.defaultStdlibLibraryPath)
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try jvmInteropNioRequireLibrary(directory, moduleName: "KSwiftKStdlib")
    let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
    return try JVMInteropNioArtifactSnapshot(directory: directory)
}

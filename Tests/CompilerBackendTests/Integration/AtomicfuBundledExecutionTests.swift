@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
@testable import RuntimeABI
import Foundation
import Testing

@Suite(.serialized)
struct AtomicfuBundledExecutionTests {
    private var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Atomicfu")
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: fixtureDirectory.appendingPathComponent(name), encoding: .utf8)
    }

    private func fileHashes(_ directory: URL) throws -> [String: String] {
        let base = directory.standardizedFileURL
        let enumerator = try #require(FileManager.default.enumerator(at: base,
            includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: String] = [:]
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let relative = String(file.path.dropFirst(base.path.count + 1))
                result[relative] = SHA256.hex(Array(try Data(contentsOf: file)))
            }
        }
        return result
    }

    private func artifactHashes(_ path: String) throws -> [String: String] {
        let result = try fileHashes(URL(fileURLWithPath: path))
        try #require(result["manifest.json"] != nil)
        try #require(result["metadata.bin"] != nil)
        try #require(!result.isEmpty)
        return result
    }

    // Receipts survive successful owned-input cleanup in a separate sibling.
    // No failure path deletes source, executable, .o, or producer library.
    private func receipt(_ directory: URL, _ name: String, _ fields: [String: Any]) throws {
        let base = URL(fileURLWithPath: directory.path + ".receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var payload = fields
        payload["owned_directory"] = directory.path
        payload["recorded_at"] = Date().timeIntervalSince1970
        let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted])
        try bytes.write(to: base.appendingPathComponent(name + ".json"), options: .atomic)
    }

    private func compile(_ source: String, module: String, emit: EmitMode,
                         directory: URL, level: OptimizationLevel, stdlib: String?,
                         searchPaths: [String] = [], includeStdlib: Bool = true) throws -> String {
        let sourcePath = directory.appendingPathComponent(module + ".kt")
        try source.write(to: sourcePath, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent(module).path
        let options = CompilerOptions(moduleName: module, inputs: [sourcePath.path],
            outputPath: output, emit: emit, searchPaths: searchPaths,
            target: defaultTargetTriple(), optLevel: level,
            includeStdlib: includeStdlib, stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false)
        try #require(options.stdlibLibraryPath == stdlib)
        try #require(options.includeStdlib == (includeStdlib && stdlib == nil))
        try #require(!options.allowDefaultStdlibLibrary)
        try receipt(directory, module + "-compile-start", [
            "status": "STARTED", "source_sha256": SHA256.hex(Array(Data(source.utf8))),
            "driver": "in-process CompilerDriver.runForTesting; no CLI argv",
            "inputs": options.inputs, "output": output, "module": module,
            "emit": String(describing: emit), "optimization": String(describing: level),
            "target": ["arch": options.target.arch, "vendor": options.target.vendor,
                "os": options.target.os, "os_version": options.target.osVersion.map { $0 as Any } ?? NSNull()],
            "stdlib": stdlib ?? "SOURCE",
            "search_paths": searchPaths, "allow_default_stdlib": false])
        let started = Date()
        let result = makeTestDriver().runForTesting(options: options)
        // Capture actual result before any assertion or cleanup.
        try receipt(directory, module + "-compile-result", [
            "exit": result.exitCode, "seconds": Date().timeIntervalSince(started),
            "diagnostics": result.diagnostics.map {
                ["code": $0.code, "severity": String(describing: $0.severity), "message": $0.message]
            }, "owned_file_sha256": try fileHashes(directory)])
        try assertCompilationSucceeded(result, context: module)
        return emit == .library ? output + ".kklib" : output
    }

    private func execute(_ executable: String, expectedFile: String, directory: URL) throws {
        let expected = try Data(contentsOf: fixtureDirectory.appendingPathComponent(expectedFile))
        let started = Date()
        try receipt(directory, "run-start", ["status": "STARTED", "executable": executable,
            "arguments": [String](), "timeout_seconds": 10,
            "executable_sha256": SHA256.hex(Array(try Data(contentsOf: URL(fileURLWithPath: executable)))),
            "expected_sha256": SHA256.hex(Array(expected))])
        do {
            let result = try CommandRunner.run(executable: executable, arguments: [], timeout: 10)
            try runReceipt(result, directory: directory, elapsed: Date().timeIntervalSince(started), status: "COMPLETED")
            // CommandRunner exposes decoded UTF-8 streams, not raw process Data.
            // ASCII fixture expectations make replacement-decoded invalid bytes fail.
            try #require(result.exitCode == 0, "\(result.stderr)")
            try #require(Data(result.stdout.utf8) == expected)
            try #require(result.stderr.isEmpty)
        } catch {
            if case let CommandRunnerError.nonZeroExit(result) = error {
                try runReceipt(result, directory: directory, elapsed: Date().timeIntervalSince(started), status: "NONZERO")
            } else {
                try receipt(directory, "run-error", ["status": "ERROR", "error": String(describing: error),
                    "seconds": Date().timeIntervalSince(started),
                    "stream_limit": "CommandRunner errors expose descriptions; raw timeout bytes are unavailable here"])
            }
            throw error
        }
    }

    private func runReceipt(_ result: CommandResult, directory: URL, elapsed: TimeInterval, status: String) throws {
        try receipt(directory, "run-result", ["status": status, "exit": result.exitCode,
            "seconds": elapsed, "stdout_decoded_utf8": result.stdout, "stderr_decoded_utf8": result.stderr,
            "stream_limit": "CommandRunner String(decoding: UTF8); not arbitrary raw bytes"])
    }

    private func retainFailure(_ directory: URL, _ error: Error, dependencies: [String]) {
        var after: [String: Any] = [:]
        for path in dependencies {
            do { after[path] = try artifactHashes(path) }
            catch { after[path] = ["hash_error": String(describing: error)] }
        }
        try? receipt(directory, "failure", ["status": "FAIL_RETAINED", "error": String(describing: error),
            "owned_file_sha256": (try? fileHashes(directory)) ?? [:], "dependencies_after": after])
        Issue.record("Atomicfu failure inputs and outputs retained at \(directory.path); receipts at \(directory.path).receipts")
    }

    @Test(arguments: [false, true], [0, 2])
    func scalarArraysTraceExecuteThroughRealKernels(library: Bool, optimization: Int) throws {
        try runFixture("scalar-arrays-trace", library: library, optimization: optimization)
    }

    @Test(arguments: [false, true], [0, 2])
    func ownedLocksAndParkingExecuteThroughRealKernels(library: Bool, optimization: Int) throws {
        try runFixture("locks-parking", library: library, optimization: optimization)
    }

    private func runFixture(_ name: String, library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dependencies: [String] = []
        do {
            let stdlib = library ? try testStdlibArtifactPath() : nil
            if let stdlib { dependencies.append(stdlib) }
            let before = try stdlib.map(artifactHashes)
            if let before { try receipt(directory, "stdlib-before", ["file_sha256": before]) }
            let executable = try compile(fixture(name + ".kt"), module: "Atomicfu_" + name.replacingOccurrences(of: "-", with: "_"),
                emit: .executable, directory: directory, level: level, stdlib: stdlib)
            try execute(executable, expectedFile: name + ".expected", directory: directory)
            if let stdlib {
                let after = try artifactHashes(stdlib)
                try receipt(directory, "stdlib-after", ["file_sha256": after])
                try #require(after == before)
            }
            try receipt(directory, "success", ["status": "PASS", "owned_file_sha256": try fileHashes(directory)])
            try FileManager.default.removeItem(at: directory) // success-only owned cleanup
        } catch {
            retainFailure(directory, error, dependencies: dependencies)
            throw error
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func producerAndSeparateConsumerKeepPrivateFieldsAndPublishedApi(library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dependencies: [String] = []
        do {
            let consumerStdlib = try testStdlibArtifactPath()
            dependencies.append(consumerStdlib)
            let stdlib = library ? consumerStdlib : nil
            let stdlibBefore = try artifactHashes(consumerStdlib)
            try receipt(directory, "stdlib-before", ["path": consumerStdlib, "file_sha256": stdlibBefore])
            let producer = try compile(fixture("producer.kt"), module: "AtomicfuProducer",
                emit: .library, directory: directory, level: level, stdlib: stdlib)
            dependencies.append(producer)
            let producerBefore = try artifactHashes(producer)
            try receipt(directory, "producer-before", ["path": producer, "file_sha256": producerBefore])
            let metadata = try String(contentsOfFile: producer + "/metadata.bin", encoding: .utf8)
            let records = MetadataDecoder().decode(metadata)
            try #require(records.contains { $0.fqName == "atomicfuproducer.newCounter" })
            try #require(records.contains { $0.fqName == "atomicfuproducer.nullableCounter" })
            try #require(records.contains { $0.fqName == "atomicfuproducer.bump" && $0.isInline })
            // A normal user producer excludes bundled declarations from metadata.
            // Both consumers use the actual fresh Stdlib dependency and separate
            // ordinary producer, never relabeling a user library as Stdlib.
            let executable = try compile(fixture("consumer.kt"), module: "AtomicfuSeparateConsumer",
                emit: .executable, directory: directory, level: level, stdlib: consumerStdlib,
                searchPaths: [producer])
            try execute(executable, expectedFile: "consumer.expected", directory: directory)
            let producerAfter = try artifactHashes(producer)
            let stdlibAfter = try artifactHashes(consumerStdlib)
            try receipt(directory, "dependencies-after", ["producer_sha256": producerAfter, "stdlib_sha256": stdlibAfter])
            try #require(producerAfter == producerBefore)
            try #require(stdlibAfter == stdlibBefore)
            try receipt(directory, "success", ["status": "PASS", "owned_file_sha256": try fileHashes(directory)])
            try FileManager.default.removeItem(at: directory) // only after both stages completed and matched
        } catch {
            retainFailure(directory, error, dependencies: dependencies)
            throw error
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func explicitRecordingRingSnapshotsAndNativeNoneControls(library: Bool, optimization: Int) throws {
        try runFixture("recording-trace-ring", library: library, optimization: optimization)
    }

    @Test(arguments: [false, true], [0, 2])
    func explicitScalarRecordingUsesGenuineSuccessOnlyModifications(library: Bool, optimization: Int) throws {
        try runFixture("recording-trace-scalars", library: library, optimization: optimization)
    }

    @Test(arguments: [false, true], [0, 2])
    func recordingCallbacksAndFailuresPreserveEvaluationAndCommittedState(library: Bool, optimization: Int) throws {
        try runFixture("recording-trace-effects", library: library, optimization: optimization)
    }

    @Test(arguments: [false, true], [0, 2])
    func recordingSessionAndScalarCrossActualProducerConsumer(library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dependencies: [String] = []
        do {
            // The independent consumer always imports actual bundled library and producer.
            let consumerStdlib = try testStdlibArtifactPath()
            dependencies.append(consumerStdlib)
            let stdlibBefore = try artifactHashes(consumerStdlib)
            try receipt(directory, "stdlib-before", ["path": consumerStdlib, "file_sha256": stdlibBefore])
            let producerStdlib = library ? consumerStdlib : nil
            let producer = try compile(fixture("recording-trace-producer.kt"), module: "RecordingTraceProducer",
                emit: .library, directory: directory, level: level, stdlib: producerStdlib)
            dependencies.append(producer)
            let producerBefore = try artifactHashes(producer)
            try receipt(directory, "producer-before", ["path": producer, "file_sha256": producerBefore])
            let metadata = try String(contentsOfFile: producer + "/metadata.bin", encoding: .utf8)
            let rows = MetadataDecoder().decode(metadata)
            try #require(rows.contains { $0.fqName == "recordingproducer.session" })
            try #require(rows.contains { $0.fqName == "recordingproducer.counter" })
            try #require(rows.contains { $0.fqName == "recordingproducer.bump" && $0.isInline })
            try #require(!rows.contains { $0.fqName == "recordingproducer.HiddenEvent" })
            let executable = try compile(fixture("recording-trace-consumer.kt"), module: "RecordingTraceConsumer",
                emit: .executable, directory: directory, level: level, stdlib: consumerStdlib,
                searchPaths: [producer])
            try execute(executable, expectedFile: "recording-trace-consumer.expected", directory: directory)
            let producerAfter = try artifactHashes(producer)
            let stdlibAfter = try artifactHashes(consumerStdlib)
            try receipt(directory, "dependencies-after", ["producer_sha256": producerAfter, "stdlib_sha256": stdlibAfter])
            try #require(producerBefore == producerAfter && stdlibBefore == stdlibAfter)
            try receipt(directory, "success", ["status": "PASS", "owned_file_sha256": try fileHashes(directory)])
            try FileManager.default.removeItem(at: directory)
        } catch {
            retainFailure(directory, error, dependencies: dependencies)
            throw error
        }
    }
    // Survival of these ordinary registered objects is a compatibility control,
    // not automatic box-reclamation evidence. Runtime heap-count tests below
    // the public ABI establish the managed-payload tracing/release contract.
    @Test(arguments: [false, true], [0, 2])
    func managedPayloadCompatibilityControls(library: Bool, optimization: Int) throws {
        try runFixture("gc-boundary", library: library, optimization: optimization)
    }

    @Test(arguments: [false, true], [0, 2])
    func managedPayloadProducerConsumerCompatibility(library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dependencies: [String] = []
        do {
            let consumerStdlib = try testStdlibArtifactPath()
            dependencies.append(consumerStdlib)
            let stdlib = library ? consumerStdlib : nil
            let stdlibBefore = try artifactHashes(consumerStdlib)
            try receipt(directory, "stdlib-before", ["path": consumerStdlib, "file_sha256": stdlibBefore])
            let producer = try compile(fixture("gc-producer.kt"), module: "AtomicfuLifetimeProducer",
                emit: .library, directory: directory, level: level, stdlib: stdlib)
            dependencies.append(producer)
            let producerBefore = try artifactHashes(producer)
            try receipt(directory, "producer-before", ["path": producer, "file_sha256": producerBefore])
            let metadata = try String(contentsOfFile: producer + "/metadata.bin", encoding: .utf8)
            let records = MetadataDecoder().decode(metadata)
            try #require(records.contains { $0.fqName == "lifetime.producer.LifetimeOwner" })
            try #require(records.contains { $0.fqName == "lifetime.producer.LifetimeOwner.collectAndCheck" })
            try #require(records.contains { $0.fqName == "lifetime.producer.LifetimeOwner.dropAndCheck" })
            let executable = try compile(fixture("gc-consumer.kt"), module: "AtomicfuLifetimeConsumer",
                emit: .executable, directory: directory, level: level, stdlib: consumerStdlib,
                searchPaths: [producer])
            try execute(executable, expectedFile: "gc-consumer.expected", directory: directory)
            let producerAfter = try artifactHashes(producer)
            let stdlibAfter = try artifactHashes(consumerStdlib)
            try receipt(directory, "dependencies-after", ["producer_sha256": producerAfter, "stdlib_sha256": stdlibAfter])
            try #require(producerAfter == producerBefore)
            try #require(stdlibAfter == stdlibBefore)
            try receipt(directory, "success", ["status": "PASS", "owned_file_sha256": try fileHashes(directory)])
            try FileManager.default.removeItem(at: directory)
        } catch {
            retainFailure(directory, error, dependencies: dependencies)
            throw error
        }
    }

}

@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
@testable import RuntimeABI
import Foundation
import Testing

@Suite(.serialized)
struct KotlinxIOUtf8ContractsExecutionTests {
    private var fixtureDirectory: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Scripts/diff_cases", isDirectory: true)
    }

    private func fixtureBytes() throws -> (source: Data, expected: Data) {
        let source = try Data(contentsOf: fixtureDirectory.appendingPathComponent("kotlinx_io_utf8_contract_boundaries.kt"))
        let expected = try Data(contentsOf: fixtureDirectory.appendingPathComponent("kotlinx_io_utf8_contract_boundaries.expected"))
        try #require(SHA256.hex(Array(source)) == "e01e3214934e6a7b664ae77790c93daba00d1aba2e5e97ea99ce67e79d7b449f")
        try #require(SHA256.hex(Array(expected)) == "ef3a687f1d31d5284351bdae1335711e575a81e8d374ccf7e12fe2f1225c2185")
        return (source, expected)
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
        Issue.record("KotlinxIOUtf8 failure inputs and outputs retained at \(directory.path); receipts at \(directory.path).receipts")
    }

    @Test(arguments: [false, true], [0, 2])
    func exactJVMContractBytesThroughSourceAndLibrary(library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dependencies: [String] = []
        do {
            let stdlib = library ? try testStdlibArtifactPath() : nil
            if let stdlib { dependencies.append(stdlib) }
            let before = try stdlib.map(artifactHashes)
            if let before { try receipt(directory, "stdlib-before", ["file_sha256": before]) }
            let pinned = try fixtureBytes()
            let source = try #require(String(data: pinned.source, encoding: .utf8))
            let executable = try compile(source, module: "KUU1733Utf8Contracts", emit: .executable,
                directory: directory, level: level, stdlib: stdlib)
            try execute(executable, expectedFile: "kotlinx_io_utf8_contract_boundaries.expected", directory: directory)
            if let stdlib {
                let after = try artifactHashes(stdlib)
                try receipt(directory, "stdlib-after", ["file_sha256": after])
                try #require(after == before)
            }
            try receipt(directory, "success", ["status": "PASS", "owned_file_sha256": try fileHashes(directory)])
            try FileManager.default.removeItem(at: directory)
        } catch {
            retainFailure(directory, error, dependencies: dependencies)
            throw error
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func actualProducerAndSeparateConsumerKeepObservedGetterAndUtf8Contracts(library: Bool, optimization: Int) throws {
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
            let pinned = try fixtureBytes()
            // Insert package after the original file annotation. Both original
            // byte slices and every original helper/main body remain exact.
            let newline = try #require(pinned.source.firstIndex(of: 10))
            let split = pinned.source.index(after: newline)
            let prefix = pinned.source[..<split]
            let suffix = pinned.source[split...]
            let package = Data("package io1733producer\n\n".utf8)
            let ported = Data(prefix) + package + Data(suffix)
            try #require(Data(ported.prefix(prefix.count)) == Data(prefix))
            try #require(Data(ported.suffix(suffix.count)) == Data(suffix))
            try receipt(directory, "producer-port", ["original_sha256": SHA256.hex(Array(pinned.source)),
                "ported_sha256": SHA256.hex(Array(ported)), "inserted_package_bytes": package.count,
                "original_body_preserved": true])
            let producer = try compile(try #require(String(data: ported, encoding: .utf8)), module: "KUU1733Utf8Producer",
                emit: .library, directory: directory, level: level, stdlib: stdlib)
            dependencies.append(producer)
            let producerBefore = try artifactHashes(producer)
            try receipt(directory, "producer-before", ["path": producer, "file_sha256": producerBefore])
            let metadata = try String(contentsOfFile: producer + "/metadata.bin", encoding: .utf8)
            let records = MetadataDecoder().decode(metadata)
            try #require(records.contains { $0.fqName == "io1733producer.main" })
            try #require(records.contains { $0.fqName == "io1733producer.ObservedChars" })
            // A source-compiled user producer excludes bundled metadata. Each
            // consumer therefore loads the fresh actual Stdlib plus the ordinary
            // user producer; no relabeling a user library as Stdlib or fallback.
            let executable = try compile("fun main() { io1733producer.main() }\n", module: "KUU1733Utf8Consumer",
                emit: .executable, directory: directory, level: level, stdlib: consumerStdlib, searchPaths: [producer])
            try execute(executable, expectedFile: "kotlinx_io_utf8_contract_boundaries.expected", directory: directory)
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

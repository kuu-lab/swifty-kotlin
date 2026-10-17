@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct IOSourceRawSourceShapeExecutionTests {
    private var fixtures: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/IOSourceRawSourceShape2615")
    }

    @Test(arguments: [0, 2])
    func sourceAndFreshKlibPreserveDeclarationShapeAndInheritance(optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        var passed = false
        defer {
            if passed {
                try? files.removeItem(at: directory)
            } else {
                print("KUU2615_RETAINED_FAILURE_DIRECTORY \(directory.path)")
            }
        }

        let stdlib = try buildFreshStdlib(at: directory, optimization: level)
        let stdlibHashes = try artifactHashes(stdlib)
        try assertDeclarationMetadata(at: stdlib)

        let combined = fixtures.appendingPathComponent("Combined.kt")
        let sourceExecutable = try compileExecutable(
            inputs: [combined], module: "KUU2615SourceProbeO\(optimization)",
            output: directory.appendingPathComponent("source-probe").path,
            optimization: level, stdlib: nil, entryPoint: "kuu2615shape.combined.main"
        )
        let sourceOutput = try execute(sourceExecutable)
        try #require(sourceOutput == "source-as-raw=true\nexternal-raw-read=-1\n")
        printEvidence("source-O\(optimization)", inputs: [combined], stdlibHashes: [:], stdout: sourceOutput)

        let klibExecutable = try compileExecutable(
            inputs: [combined], module: "KUU2615KlibProbeO\(optimization)",
            output: directory.appendingPathComponent("klib-probe").path,
            optimization: level, stdlib: stdlib.path, entryPoint: "kuu2615shape.combined.main"
        )
        let klibOutput = try execute(klibExecutable)
        try #require(klibOutput == sourceOutput)
        printEvidence("stdlib-library-O\(optimization)", inputs: [combined], stdlibHashes: stdlibHashes, stdout: klibOutput)

        try assertSourceBoundaryRejected(stdlib: stdlib, optimization: level, directory: directory)

        let producerSource = fixtures.appendingPathComponent("Producer.kt")
        let producerBase = directory.appendingPathComponent("raw-source-producer").path
        let producerOptions = CompilerOptions(
            moduleName: "KUU2615ProducerO\(optimization)", inputs: [producerSource.path], outputPath: producerBase,
            emit: .library, target: defaultTargetTriple(), optLevel: level,
            stdlibLibraryPath: stdlib.path, allowDefaultStdlibLibrary: false
        )
        try #require(producerOptions.includeStdlib == false && producerOptions.stdlibLibraryPath == stdlib.path)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: producerOptions), context: "KUU-2615 producer")
        let producerKlib = URL(fileURLWithPath: producerBase + ".kklib", isDirectory: true)
        let producerHashes = try artifactHashes(producerKlib)
        let producerMetadata = MetadataDecoder().decode(try Data(contentsOf: producerKlib.appendingPathComponent("metadata.bin")))
        try #require(producerMetadata.contains { $0.kind == .class && $0.fqName == "kuu2615shape.producer.ExternalRawSource" })

        let consumer = fixtures.appendingPathComponent("Consumer.kt")
        let consumerExecutable = try compileExecutable(
            inputs: [consumer], module: "KUU2615ConsumerO\(optimization)",
            output: directory.appendingPathComponent("producer-consumer").path,
            optimization: level, stdlib: stdlib.path, searchPaths: [producerKlib.path],
            entryPoint: "kuu2615shape.consumer.main"
        )
        let bridgeOutput = try execute(consumerExecutable)
        try #require(bridgeOutput == "imported-raw-read=-1\nsource-is-closeable=true\n")
        printEvidence("producer-consumer-O\(optimization)", inputs: [producerSource, consumer],
                      stdlibHashes: stdlibHashes.merging(producerHashes) { _, new in new }, stdout: bridgeOutput)

        try #require(artifactHashes(stdlib) == stdlibHashes)
        try #require(artifactHashes(producerKlib) == producerHashes)
        passed = true
    }

    private func buildFreshStdlib(at directory: URL, optimization: OptimizationLevel) throws -> URL {
        let base = directory.appendingPathComponent("stdlib-\(optimization)").path
        let options = CompilerOptions(
            moduleName: "KSwiftKStdlib", inputs: [], outputPath: base, emit: .library,
            target: defaultTargetTriple(), optLevel: optimization,
            includeStdlib: true, stdlibOnly: true, allowDefaultStdlibLibrary: false
        )
        try #require(options.stdlibOnly && options.stdlibLibraryPath == nil && !options.allowDefaultStdlibLibrary)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "Fresh KUU-2615 stdlib")
        let path = URL(fileURLWithPath: base + ".kklib", isDirectory: true)
        let manifestData = try Data(contentsOf: path.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
        try #require(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
        return path
    }

    private func assertDeclarationMetadata(at stdlib: URL) throws {
        let records = MetadataDecoder().decode(try Data(contentsOf: stdlib.appendingPathComponent("metadata.bin")))
        let raw = try #require(records.first { $0.kind == .interface && $0.fqName == "kotlinx.io.RawSource" })
        let source = try #require(records.first { $0.kind == .interface && $0.fqName == "kotlinx.io.Source" })
        try #require(raw.visibility == .public && !raw.isSealedClass)
        try #require(raw.superFQName == "kotlin.AutoCloseable")
        try #require(source.visibility == .public && source.isSealedClass)
        try #require(source.superFQName == "kotlinx.io.RawSource")
        print("KUU2615_METADATA RawSource=public/open->kotlin.AutoCloseable Source=public/sealed->kotlinx.io.RawSource")
    }

    private func assertSourceBoundaryRejected(stdlib: URL, optimization: OptimizationLevel, directory: URL) throws {
        let source = fixtures.appendingPathComponent("SourceBoundaryNegative.kt")
        let output = directory.appendingPathComponent("source-boundary-negative-\(optimization)").path
        let options = CompilerOptions(
            moduleName: "KUU2615Negative", inputs: [source.path], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: optimization, includeStdlib: false,
            stdlibLibraryPath: stdlib.path, allowDefaultStdlibLibrary: false
        )
        let result = makeTestDriver().runForTesting(options: options)
        let errors = result.diagnostics.filter { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0070" }
        try #require(result.exitCode != 0 && errors.count == 1, "Sealed Source boundary must reject an external subtype: \(result.diagnostics)")
        print("KUU2615_NEGATIVE source-boundary-O\(optimization.rawValue) diagnostic=KSWIFTK-SEMA-0070")
    }

    private func compileExecutable(
        inputs: [URL], module: String, output: String, optimization: OptimizationLevel,
        stdlib: String?, searchPaths: [String] = [], entryPoint: String
    ) throws -> URL {
        let options = CompilerOptions(
            moduleName: module, inputs: inputs.map(\.path), outputPath: output, emit: .executable,
            searchPaths: searchPaths, target: defaultTargetTriple(), optLevel: optimization,
            includeStdlib: stdlib == nil, stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: false, entryPointFQName: entryPoint
        )
        try #require(options.includeStdlib == (stdlib == nil))
        try #require(options.stdlibLibraryPath == stdlib && options.searchPaths == searchPaths)
        try #require(options.entryPointFQName == entryPoint)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
        let executable = URL(fileURLWithPath: output)
        try #require(FileManager.default.isExecutableFile(atPath: output))
        return executable
    }

    private func execute(_ executable: URL) throws -> String {
        let result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 30)
        try #require(result.exitCode == 0, "exit=\(result.exitCode), stderr=\(result.stderr)")
        try #require(result.stderr.isEmpty)
        return result.stdout
    }

    private func artifactHashes(_ directory: URL) throws -> [String: String] {
        let base = directory.standardizedFileURL.resolvingSymlinksInPath()
        let baseComponents = base.pathComponents
        let enumerator = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]))
        var hashes: [String: String] = [:]
        for case let unnormalizedFile as URL in enumerator {
            let file = unnormalizedFile.standardizedFileURL.resolvingSymlinksInPath()
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let components = file.pathComponents
            try #require(components.starts(with: baseComponents), "KLIB artifact escaped its root: \(file.path)")
            let relative = components.dropFirst(baseComponents.count).joined(separator: "/")
            hashes[relative] = FileFingerprint.sha256Hex(try Data(contentsOf: file))
        }
        try #require(hashes["manifest.json"] != nil && hashes["metadata.bin"] != nil)
        return hashes
    }

    private func printEvidence(_ lane: String, inputs: [URL], stdlibHashes: [String: String], stdout: String) {
        let inputHashes = inputs.map { "\($0.lastPathComponent):\(FileFingerprint.sha256Hex((try? Data(contentsOf: $0)) ?? Data()))" }
            .joined(separator: ",")
        let artifactHash = FileFingerprint.sha256Hex(Data((stdlibHashes.sorted { $0.key < $1.key }.description).utf8))
        print("KUU2615_PASS lane=\(lane) inputs=\(inputHashes) artifact_hash=\(artifactHash) stdout_sha256=\(FileFingerprint.sha256Hex(Data(stdout.utf8))) stdout=\(stdout.debugDescription)")
    }
}

@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], ["O0", "O2"])
    func testCallByOmittedVarargOriginalOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("original29", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "7abd3a398297c9914a6e6b8613a7c2ff80469dd456adc26ce7ac7055f4c38621",
            consumerHash: "0c0edbcb0ddb1ca6c66a90ecb90047a68392673eb1deb5ff8e456a5a72a86a6a",
            expectedHash: "f2390754f5212c34bb73cd268d7094950bb52b0dc80f857f194e490d26f4b3c1")
    }

    @Test(arguments: [false, true], ["O0", "O2"])
    func testCallByTypedOptionalVarargDefaultOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("typed16", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "866d39193ae79ad624d9fad901ae25811dffdcee822e897f9f16f7adc2dc3765",
            consumerHash: "84746e06e7e545049018e4893f20f136782b681181bda958cd9108d63d7da0a3",
            expectedHash: "0b03116b390e6af0fc28247791fa8a966f0a172a35fdb5f1b294c7032ffd4d53")
    }

    /// Includes reference-array identity/component controls. These are strict
    /// Kotlin expectations, so this method cannot pass while known gaps remain.
    @Test(arguments: [false, true], ["O0", "O2"])
    func testOrdinaryConstructorPackedCallByOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("constructor32", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "08250f569829e5e566f3bfee55a0160b5f03a4529a1163fa4c2e192b5b40dc80",
            consumerHash: "e05499d3906c2ead0e4438e2ddc14b21e6518fecd9d02b9b8dcb66856a430103",
            expectedHash: "bc84becec92ffb576ab46a4ac6eada4a211983beafcfb0a49dad1dfad90c32dc")
    }

    @Test(arguments: [false, true], ["O0", "O2"])
    func testVarargArrayIdentityAndComponentOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("array16", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "bbbc905abf56591e950202f2d3e4fafafb0c709965d62ae27ed4b58856ffc850",
            consumerHash: "a73dbdf9a2f8dd28b9b189b9c264f97825fa60ba922409582445f5abed3a0007",
            expectedHash: "4b6be921ec6f00f618dd2ed277696b4f62e5d2adc5bed8dfffc98c503af69acd")
    }

    @Test(arguments: [false, true], ["O0", "O2"])
    func testReifiedArrayComponentAndNonVarargABIOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("reified6", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "e1fc6dca732c71cf4a7bed11b35525120c9f163216107ec4e362ee3257204beb",
            consumerHash: "238ce39efa561d1e2562569cac095d0e6d4c1dbaa1b75c41db74610a7c47dd38",
            expectedHash: "41b356965661303913009603722634206668fe04cf53a9169f83e3e3f70facbe")
    }

    @Test(arguments: [false, true], ["O0", "O2"])
    func testCallByStdlibArrayProducersAndListBridgesOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("stdlib14", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "167e2befe68514aeb9a1774319613c3f2d4c20e6e6844268d0223ab3623adc2f",
            consumerHash: "678b5cc7aa6140234b4211b14c4582652dc60461d427988560bbec28684b6f77",
            expectedHash: "f26678038fbeb882595391237f1ba5198906b457799b6101344c1403c9853dd0")
    }

    @Test(arguments: [false, true], ["O0", "O2"])
    func testCallByReifiedDefaultSupplierCaptureOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("default2", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "c72ff7fd185e9f7c2c7eb7f89ae7024727c0ce51387b608cec00dc792f324c8f",
            consumerHash: "0db06da63881adf6067f89c652c01a0a09e711f5314fcbbd413cd4bd76cab878",
            expectedHash: "bcb2092d7dcd2c73c65f7181c164aeb51f985d02e5ef60eb8dc040f47937d42e")
    }

    @Test(arguments: [false, true], ["O0", "O2"])
    func testCallByTwoReifiedAndVirtualMemberABIOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("abi8", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "ce150fd6ef80ba4eefd953840460f5ccdd71916988f3dcdd6361ef7baaa40a7c",
            consumerHash: "50db2c04029d3ee2fbeadec464b11c21808023d75097047c085d3b95427da007",
            expectedHash: "08d63b1f5e336b5a9fead1cde1deb2928045f21121a0be60a1490eba7e3b6af2")
    }

    @Test(arguments: [false, true], ["O0", "O2"])
    func testCallByScalarPackedAdaptersAndInlineVarargDefaultOracle(useProducerLibrary: Bool, level: String) throws {
        try runPackedCallByFixture("adapter5", useProducerLibrary: useProducerLibrary, level: level,
            producerHash: "e4c6fcb5fb4624b6feebf3a70b580f2b93000990e5150bdc69a41856c965c93a",
            consumerHash: "f526dc432436c1bdb223d4b5f66bfb94b7f23b17e8204d677cbc0aaa650d1d38",
            expectedHash: "465959369b79280ff4519194bb746c551cacdc602f0d8157a0f6a743ccdbfd0b")
    }

    private func runPackedCallByFixture(
        _ fixture: String, useProducerLibrary: Bool, level: String,
        producerHash: String, consumerHash: String, expectedHash: String
    ) throws {
        // Swift Testing's parameter values must be Sendable. Keep the public
        // compiler enum inside this synchronous helper and preserve both lanes.
        let optimizationLevel = try #require(
            ["O0": OptimizationLevel.O0, "O2": .O2][level],
            "Unexpected packed callBy optimization lane: \(level)")
        let fixtures = packedCallByRepositoryRoot().appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/CallByOmittedVararg/" + fixture, isDirectory: true)
        let producer = try Data(contentsOf: fixtures.appendingPathComponent("producer.kt"))
        let consumer = try Data(contentsOf: fixtures.appendingPathComponent("consumer.kt"))
        let expected = try Data(contentsOf: fixtures.appendingPathComponent("expected.stdout"))
        try #require(FileFingerprint.sha256Hex(producer) == producerHash)
        try #require(FileFingerprint.sha256Hex(consumer) == consumerHash)
        try #require(FileFingerprint.sha256Hex(expected) == expectedHash)
        let stdlib = try packedCallByStdlibSnapshot(required: useProducerLibrary)
        defer { stdlib?.expectUnchanged() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completedProof = false
        defer {
            if completedProof {
                try? FileManager.default.removeItem(at: directory)
            } else {
                let evidence: [String: Any] = [
                    "status": "FAILED_OR_INCOMPLETE_PROOF_RETAINED",
                    "directory": directory.path,
                    "input_artifact_and_executable_cleanup": false,
                    "owned_descendant_reap": "MUST_BE_OBSERVED_BY_OUTER_GATE",
                ]
                if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]) {
                    try? data.write(to: directory.appendingPathComponent("failure-preservation.json"))
                }
                print("Retained failed fixture: " + directory.path)
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
        let moduleName = "KUU1768Packed_" + fixture
        var library: PackedCallByArtifactSnapshot?
        defer { library?.expectUnchanged() }
        if useProducerLibrary {
            let base = directory.appendingPathComponent("producer")
            let options = CompilerOptions(
                moduleName: moduleName, inputs: [producerInput.path], outputPath: base.path,
                emit: .library, target: TargetTriple.hostDefault(), optLevel: optimizationLevel,
                stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false)
            try #require(options.inputs == [producerInput.path])
            try #require(!options.includeStdlib && !options.allowDefaultStdlibLibrary)
            try #require(options.stdlibLibraryPath == stdlib?.directory.path)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "Packed callBy producer")
            let artifact = base.appendingPathExtension("kklib")
            try packedCallByRequireLibrary(artifact, moduleName: moduleName)
            let metadata = MetadataDecoder().decode(String(decoding: try Data(contentsOf: artifact.appendingPathComponent("metadata.bin")), as: UTF8.self))
            let constructors = metadata.filter { $0.kind == .constructor && $0.valueParameterIsVararg.contains(true) }
            if fixture == "reified6" {
                let reified = metadata.filter { $0.kind == .function && $0.isInline && !$0.reifiedTypeParameterIndices.isEmpty }
                try #require(reified.count == 4, "Real producer exports all four non-vararg reified bodies")
                for function in reified {
                    try #require(function.externalLinkName?.hasPrefix("kk_fn_") == true)
                    try #require(function.reifiedTypeParameterIndices == [0])
                }
                let inlineDirectory = artifact.appendingPathComponent("inline-kir")
                let inlineFiles = try FileManager.default.contentsOfDirectory(atPath: inlineDirectory.path)
                try #require(inlineFiles.filter { $0.hasSuffix(".kirbin") }.count >= 4)
            } else if fixture == "adapter5" {
                let function = try #require(metadata.first { $0.fqName == "inlineDefaultWords" })
                try #require(function.isInline && function.valueParameterIsVararg == [true])
                try #require(function.valueParameterHasDefaultValues == [true])
                let stubLink = try #require(function.defaultStubExternalLinkName)
                try #require(!stubLink.isEmpty)
                let inlineDirectory = artifact.appendingPathComponent("inline-kir")
                for name in [function.mangledName, stubLink] {
                    let file = inlineDirectory.appendingPathComponent(MetadataEncoder.inlineKIRFileName(for: name))
                    try #require(FileManager.default.fileExists(atPath: file.path), "Both normal and default-stub real producer inline bodies are required")
                }
                let generic = try #require(metadata.first { $0.fqName == "genericArrayIdentity" })
                try #require(generic.callableTypeParameterSignatures.count == 1 && generic.valueParameterIsVararg == [true])
            } else if fixture == "abi8" {
                let ordered = try #require(metadata.first { $0.fqName == "typedPair" })
                try #require(ordered.isInline && ordered.reifiedTypeParameterIndices == [0, 1])
                try #require(ordered.valueParameterHasDefaultValues == [true])
                try #require(ordered.defaultStubExternalLinkName?.isEmpty == false)
                let inlineFile = artifact.appendingPathComponent("inline-kir")
                    .appendingPathComponent(MetadataEncoder.inlineKIRFileName(for: ordered.mangledName))
                try #require(FileManager.default.fileExists(atPath: inlineFile.path))
            } else if fixture == "default2" {
                let capture = try #require(metadata.first { $0.fqName == "defaultArray" })
                try #require(capture.isInline && capture.reifiedTypeParameterIndices == [0])
                try #require(capture.valueParameterHasDefaultValues == [true])
                try #require(capture.defaultStubExternalLinkName?.isEmpty == false)
                let inlineFile = artifact.appendingPathComponent("inline-kir")
                    .appendingPathComponent(MetadataEncoder.inlineKIRFileName(for: capture.mangledName))
                try #require(FileManager.default.fileExists(atPath: inlineFile.path))
            } else if fixture == "stdlib14" {
                let forwarded = try #require(metadata.first { $0.fqName == "forwardedWords" })
                try #require(forwarded.isInline && forwarded.valueParameterIsVararg == [true])
                try #require(forwarded.reifiedTypeParameterIndices.isEmpty)
                try #require(forwarded.externalLinkName?.hasPrefix("kk_fn_") == true)
                let inlineFile = artifact.appendingPathComponent("inline-kir")
                    .appendingPathComponent(MetadataEncoder.inlineKIRFileName(for: forwarded.mangledName))
                try #require(FileManager.default.fileExists(atPath: inlineFile.path))
            } else {
                try #require(!constructors.isEmpty, "Real producer must export vararg constructor metadata")
            }
            for constructor in constructors {
                try #require(constructor.externalLinkName?.hasPrefix("kk_fn_") == true)
                try #require(constructor.valueParameterIsVararg.count == constructor.valueParameterHasDefaultValues.count)
                if constructor.valueParameterHasDefaultValues.contains(true) {
                    try #require(constructor.defaultStubExternalLinkName?.isEmpty == false)
                }
            }
            library = try PackedCallByArtifactSnapshot(directory: artifact)
        }
        let executable = directory.appendingPathComponent("consumer")
        let inputs = useProducerLibrary ? [consumerInput.path] : [producerInput.path, consumerInput.path]
        let searchPaths = library.map { [$0.directory.path] } ?? []
        let options = CompilerOptions(
            moduleName: moduleName + "Consumer", inputs: inputs, outputPath: executable.path,
            emit: .executable, searchPaths: searchPaths, target: TargetTriple.hostDefault(), optLevel: optimizationLevel,
            stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false)
        try #require(options.inputs == inputs && options.searchPaths == searchPaths)
        try #require(options.includeStdlib == !useProducerLibrary && !options.allowDefaultStdlibLibrary)
        try #require(options.stdlibLibraryPath == stdlib?.directory.path)
        if useProducerLibrary { try #require(!options.inputs.contains(producerInput.path)) }
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "Packed callBy consumer")
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
            try #require(try packedCallByArtifactHashes(library.directory) == library.hashes)
        }
        if let stdlib {
            try #require(try packedCallByArtifactHashes(stdlib.directory) == stdlib.hashes)
        }
        completedProof = true
    }
}

private func packedCallByRepositoryRoot(file: StaticString = #filePath) -> URL {
    var root = URL(fileURLWithPath: String(describing: file))
    for _ in 0..<4 { root.deleteLastPathComponent() }
    return root
}

private struct PackedCallByArtifactSnapshot {
    let directory: URL
    let hashes: [String: String]
    init(directory: URL) throws {
        self.directory = directory
        hashes = try packedCallByArtifactHashes(directory)
        try #require(hashes["manifest.json"] != nil && hashes["metadata.bin"] != nil)
    }
    func expectUnchanged() {
        #expect((try? packedCallByArtifactHashes(directory)) == hashes,
                "Full producer artifact file set and SHA must remain unchanged")
    }
}

private func packedCallByArtifactHashes(_ directory: URL) throws -> [String: String] {
    let root = directory.resolvingSymlinksInPath().standardizedFileURL
    let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
    var hashes: [String: String] = [:]
    for case let file as URL in enumerator {
        guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
        hashes[String(file.path.dropFirst(root.path.count + 1))] = FileFingerprint.sha256Hex(try Data(contentsOf: file))
    }
    return hashes
}

private func packedCallByRequireLibrary(_ directory: URL, moduleName: String) throws {
    let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    try #require(manifest["moduleName"] as? String == moduleName)
    try #require(manifest["formatVersion"] as? Int == 1)
    try #require(manifest["sourceVarargStorageABI"] as? String == "array-v1")
    try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
    let objects = try #require(manifest["objects"] as? [String])
    try #require(!objects.isEmpty)
    for object in objects { try #require(!(try Data(contentsOf: directory.appendingPathComponent(object))).isEmpty) }
}

private func packedCallByStdlibSnapshot(required: Bool) throws -> PackedCallByArtifactSnapshot? {
    guard required else { return nil }
    TestStdlibCache.shared.prepare()
    let path = try #require(CompilerOptions.defaultStdlibLibraryPath)
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try packedCallByRequireLibrary(directory, moduleName: "KSwiftKStdlib")
    let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
    return try PackedCallByArtifactSnapshot(directory: directory)
}

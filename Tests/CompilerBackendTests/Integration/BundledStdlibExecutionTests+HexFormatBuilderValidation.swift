@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testHexFormatBuilderValidationRuntime(useStdlibLibrary: Bool) throws {
        try runHex1767Fixture(
            name: "hex_format_builder_validation", moduleName: "KUU1767HexBuilderValidation",
            sourceHash: "4e2b5918c354997e7d648bf4d006e97d406405142cbfc1983638ff0e32891ef3",
            expectedHash: "3c56322b81b61b4a55df03212c62fa528ec921319889bc7585cf0eae59823f5c",
            useStdlibLibrary: useStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testHexFormatBuilderCompoundRuntime(useStdlibLibrary: Bool) throws {
        try runHex1767Fixture(
            name: "hex_format_builder_compound", moduleName: "KUU1767HexBuilderCompound",
            sourceHash: "c244794566847f820c1e9612d36cc194b6fe898f0cfc14ba7a6da9c47c569564",
            expectedHash: "d2e681c791fa00b91311f3dbcee2ba541171181e5b6baa2ac89ba61a547c5e99",
            useStdlibLibrary: useStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testHexFormatBuilderBareAssignmentRuntime(useStdlibLibrary: Bool) throws {
        try runHex1767Fixture(
            name: "hex_format_builder_bare_assignment", moduleName: "KUU1767HexBuilderBareAssignment",
            sourceHash: "3de1d5688645ad7bdd3ab3e1c430acfa867f479547d3b01c21873214bc37a164",
            expectedHash: "72946c99ee810dce34e1dc4725d33a06cc208210c1c23af03932bb13cab5e752",
            useStdlibLibrary: useStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testHexFormatBuilderCompositeO2Runtime(useStdlibLibrary: Bool) throws {
        let cases = hex1767RepositoryRoot().appendingPathComponent("Scripts/diff_cases", isDirectory: true)
        let fixtures = [
            (name: "hex_format_builder_validation", packageName: "kuu1767o2.validation", sourceHash: "4e2b5918c354997e7d648bf4d006e97d406405142cbfc1983638ff0e32891ef3", expectedHash: "3c56322b81b61b4a55df03212c62fa528ec921319889bc7585cf0eae59823f5c"),
            (name: "hex_format_builder_compound", packageName: "kuu1767o2.compound", sourceHash: "c244794566847f820c1e9612d36cc194b6fe898f0cfc14ba7a6da9c47c569564", expectedHash: "d2e681c791fa00b91311f3dbcee2ba541171181e5b6baa2ac89ba61a547c5e99"),
            (name: "hex_format_builder_bare_assignment", packageName: "kuu1767o2.bare", sourceHash: "3de1d5688645ad7bdd3ab3e1c430acfa867f479547d3b01c21873214bc37a164", expectedHash: "72946c99ee810dce34e1dc4725d33a06cc208210c1c23af03932bb13cab5e752")
        ]
        var sources: [(name: String, contents: Data)] = []
        var expected = Data()
        for fixture in fixtures {
            let original = try Data(contentsOf: cases.appendingPathComponent(fixture.name + ".kt"))
            let rows = try Data(contentsOf: cases.appendingPathComponent(fixture.name + ".expected"))
            try #require(FileFingerprint.sha256Hex(original) == fixture.sourceHash)
            try #require(FileFingerprint.sha256Hex(rows) == fixture.expectedHash)
            let prefix = Data("package \(fixture.packageName)\n\n".utf8)
            var adapted = prefix
            adapted.append(original)
            try #require(Data(adapted.dropFirst(prefix.count)) == original,
                         "Only an explicit package prefix may adapt the original body")
            sources.append((fixture.name + ".kt", adapted))
            expected.append(rows)
        }
        let driver = Data("package kuu1767o2.driver\n\nfun main() {\n    kuu1767o2.validation.main()\n    kuu1767o2.compound.main()\n    kuu1767o2.bare.main()\n}\n".utf8)
        try #require(FileFingerprint.sha256Hex(driver) == "c672f411967699a158ab9679ce0282a24528210768ba905ca5adfdcfbc1e8503")
        try #require(FileFingerprint.sha256Hex(expected) == "c12336365215b31372b53218110f876c7db718093423e658affadb41bc8df821")
        try #require(expected.split(separator: 10).count == 49)
        sources.append(("Driver.kt", driver))
        try runHex1767Sources(
            sources: sources, expected: expected, moduleName: "KUU1767HexCompositeO2",
            useStdlibLibrary: useStdlibLibrary, optLevel: .O2,
            entryPointFQName: "kuu1767o2.driver.main"
        )
    }

    private func runHex1767Fixture(
        name: String, moduleName: String, sourceHash: String, expectedHash: String,
        useStdlibLibrary: Bool
    ) throws {
        let cases = hex1767RepositoryRoot().appendingPathComponent("Scripts/diff_cases", isDirectory: true)
        let source = try Data(contentsOf: cases.appendingPathComponent(name + ".kt"))
        let expected = try Data(contentsOf: cases.appendingPathComponent(name + ".expected"))
        try #require(FileFingerprint.sha256Hex(source) == sourceHash)
        try #require(FileFingerprint.sha256Hex(expected) == expectedHash)
        try runHex1767Sources(sources: [("original.kt", source)], expected: expected,
                             moduleName: moduleName, useStdlibLibrary: useStdlibLibrary, optLevel: .O0)
    }

    private func runHex1767Sources(
        sources: [(name: String, contents: Data)], expected: Data, moduleName: String,
        useStdlibLibrary: Bool, optLevel: OptimizationLevel, entryPointFQName: String? = nil
    ) throws {
        let stdlib = try hex1767StdlibSnapshot(useLibrary: useStdlibLibrary)
        defer { stdlib?.expectUnchanged() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("KUU1767_RUNTIME_DIRECTORY \(directory.path)")
        let inputs = sources.map { directory.appendingPathComponent($0.name) }
        for (source, input) in zip(sources, inputs) { try source.contents.write(to: input) }
        let executable = directory.appendingPathComponent("original")
        let options = CompilerOptions(
            moduleName: moduleName, inputs: inputs.map(\.path), outputPath: executable.path,
            emit: .executable, target: TargetTriple.hostDefault(), optLevel: optLevel,
            stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false,
            entryPointFQName: entryPointFQName
        )
        try #require(options.inputs == inputs.map(\.path))
        try #require(options.optLevel == optLevel && options.entryPointFQName == entryPointFQName)
        try #require(options.stdlibLibraryPath == stdlib?.directory.path)
        try #require(options.includeStdlib == !useStdlibLibrary)
        try #require(!options.allowDefaultStdlibLibrary)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        let executableHash = FileFingerprint.sha256Hex(try Data(contentsOf: executable))
        let execution = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
        try #require(execution.exitCode == 0, "\(execution.stderr)")
        try #require(execution.stderr.isEmpty)
        try #require(Data(execution.stdout.utf8) == expected)
        for (source, input) in zip(sources, inputs) {
            try #require(Data(contentsOf: input) == source.contents)
        }
        try stdlib?.requireUnchanged()
        try hex1767CleanupSuccessfulRuntime(
            directory: directory, executable: executable, executableHash: executableHash,
            expected: expected, lane: moduleName + (useStdlibLibrary ? "-library" : "-source") + "-O\(optLevel.rawValue)"
        )
    }
}

func hex1767RepositoryRoot(file: StaticString = #filePath) -> URL {
    var root = URL(fileURLWithPath: String(describing: file))
    for _ in 0..<4 { root.deleteLastPathComponent() }
    return root
}

struct Hex1767ArtifactSnapshot {
    let directory: URL
    let hashes: [String: String]
    var completeFileSet = false

    func requireUnchanged() throws {
        for (name, hash) in hashes {
            try #require(FileFingerprint.compute(for: directory.appendingPathComponent(name).path)?.contentHash == hash)
        }
        if completeFileSet { try #require(hex1767ArtifactHashes(directory) == hashes) }
    }

    func expectUnchanged() {
        for (name, hash) in hashes {
            #expect(FileFingerprint.compute(for: directory.appendingPathComponent(name).path)?.contentHash == hash,
                    "Artifact changed during regression: \(name)")
        }
        if completeFileSet {
            let current = try? hex1767ArtifactHashes(directory)
            #expect(current == hashes, "The user artifact file set and hashes must remain fixed")
        }
    }
}

func hex1767ArtifactHashes(_ directory: URL) throws -> [String: String] {
    let canonicalDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
    let enumerator = try #require(FileManager.default.enumerator(at: canonicalDirectory,
                                                                includingPropertiesForKeys: [.isRegularFileKey]))
    var hashes: [String: String] = [:]
    for case let file as URL in enumerator {
        guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
        let relative = String(file.path.dropFirst(canonicalDirectory.path.count + 1))
        hashes[relative] = FileFingerprint.sha256Hex(try Data(contentsOf: file))
    }
    return hashes
}

func hex1767StdlibSnapshot(useLibrary: Bool) throws -> Hex1767ArtifactSnapshot? {
    guard useLibrary else { return nil }
    TestStdlibCache.shared.prepare()
    let path = try #require(CompilerOptions.defaultStdlibLibraryPath,
                           "Library coverage requires the published stdlib artifact")
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    var isDirectory: ObjCBool = false
    try #require(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue)
    let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let json = try #require(JSONSerialization.jsonObject(with: manifest) as? [String: Any])
    try #require(json["moduleName"] as? String == "KSwiftKStdlib")
    try #require(json["formatVersion"] as? Int == 1)
    try #require(json["kotlinLanguageVersion"] as? String == "2.3.10")
    try #require(json["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
    let metadata = try Data(contentsOf: directory.appendingPathComponent("metadata.bin"))
    try #require(!metadata.isEmpty)
    let records = MetadataDecoder().decode(String(decoding: metadata, as: UTF8.self))
    let owner = "kotlin.text.HexFormat.BytesHexFormat.Builder"
    let builder = try #require(records.first { $0.kind == .class && $0.fqName == owner })
    let offsets = try hex1767FieldOffsets(builder)
    try #require(builder.declaredFieldCount == offsets.count)
    try #require(Set(offsets.values).count == offsets.count,
                 "Canonical storage must not double-count backing/property aliases")
    for name in ["bytesPerLine", "bytesPerGroup", "byteSeparator", "bytePrefix", "byteSuffix"] {
        let property = try #require(records.first { $0.kind == .property && $0.fqName == owner + "." + name })
        try #require(property.propertySetterExternalLinkName?.isEmpty == false,
                     "Library mode must contain the compiled validating setter")
        try #require(offsets[property.fqName] != nil,
                     "Fresh producer metadata must export the default getter's property slot")
    }
    return Hex1767ArtifactSnapshot(directory: directory, hashes: [
        "manifest.json": FileFingerprint.sha256Hex(manifest),
        "metadata.bin": FileFingerprint.sha256Hex(metadata),
    ])
}

func hex1767FieldOffsets(_ record: MetadataRecord) throws -> [String: Int] {
    var offsets: [String: Int] = [:]
    for entry in (record.fieldOffsets ?? "").split(separator: ",") {
        let components = entry.split(separator: "@", maxSplits: 1)
        try #require(components.count == 2)
        let name = String(components[0])
        let offset = try #require(Int(components[1]))
        try #require(offsets[name] == nil)
        offsets[name] = offset
    }
    return offsets
}

// Called only after successful compilation, CommandRunner's completed process,
// exact stdout/stderr checks, and unchanged source/library checks. Failures retain
// the printed UUID directory; neither caches nor compiler binaries live here.
func hex1767CleanupSuccessfulRuntime(
    directory: URL, executable: URL, executableHash: String, expected: Data, lane: String
) throws {
    let files = FileManager.default
    let owned = directory.standardizedFileURL
    try #require(owned.deletingLastPathComponent() == files.temporaryDirectory.standardizedFileURL)
    try #require(UUID(uuidString: owned.lastPathComponent) != nil)
    try #require(FileFingerprint.sha256Hex(Data(contentsOf: executable)) == executableHash)
    let hashes = try hex1767ArtifactHashes(owned)
    var sizes: [String: Int] = [:]
    for name in hashes.keys {
        sizes[name] = try Data(contentsOf: owned.appendingPathComponent(name)).count
    }
    let receiptRoot = ProcessInfo.processInfo.environment["KSWIFTK_HEX1767_RECEIPT_DIRECTORY"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? files.temporaryDirectory.appendingPathComponent("KUU1767-runtime-receipts", isDirectory: true)
    try #require(!receiptRoot.standardizedFileURL.path.hasPrefix(owned.path + "/"))
    try files.createDirectory(at: receiptRoot, withIntermediateDirectories: true)
    let receipt = receiptRoot.appendingPathComponent(owned.lastPathComponent + ".json")
    let beforeAttributes = try files.attributesOfFileSystem(forPath: owned.path)
    let freeBefore = try #require(beforeAttributes[.systemFreeSize] as? NSNumber).uint64Value
    var proof: [String: Any] = [
        "status": "PASS_PROOF_BEFORE_CLEANUP", "lane": lane, "directory": owned.path,
        "native_returned_after_exit": true, "exit_code": 0, "runtime_timeout_seconds": 10,
        "stdout_exact": true, "stderr_empty": true,
        "expected_sha256": FileFingerprint.sha256Hex(expected),
        "executable": executable.path, "executable_sha256_before_after": executableHash,
        "generated_files_sha256": hashes, "generated_files_bytes": sizes,
        "free_bytes_before_cleanup": freeBefore
    ]
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]).write(to: receipt, options: .atomic)
    try files.removeItem(at: owned)
    try #require(!files.fileExists(atPath: owned.path))
    proof["status"] = "PASS_CLEANED"
    let afterAttributes = try files.attributesOfFileSystem(forPath: receiptRoot.path)
    proof["free_bytes_after_cleanup"] = try #require(afterAttributes[.systemFreeSize] as? NSNumber).uint64Value
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]).write(to: receipt, options: .atomic)
    print("KUU1767_RUNTIME_RECEIPT \(receipt.path)")
}

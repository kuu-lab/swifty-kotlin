@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    /// false compiles the original producer and consumer together from source.
    /// true emits a real user .kklib first, then compiles only the separate
    /// consumer with that library and the explicit published stdlib artifact.
    @Test(arguments: [false, true], [0, 2])
    func testHexFormatSetterProducerRoundTripRuntime(useProducerLibrary: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try #require(optLevel == .O0 || optLevel == .O2)
        let fixtures = hex1767RepositoryRoot().appendingPathComponent("Tests/CompilerBackendTests/Fixtures/HexFormatSetterControl", isDirectory: true)
        let producerSource = try Data(contentsOf: fixtures.appendingPathComponent("producer.kt"))
        let consumerSource = try Data(contentsOf: fixtures.appendingPathComponent("consumer.kt"))
        let expected = try Data(contentsOf: fixtures.appendingPathComponent("expected.stdout"))
        try #require(FileFingerprint.sha256Hex(producerSource) == "440b363c543fa1e1b6bc063e4d08ea6627b373235e7ef8e9319880a31af60f28")
        try #require(FileFingerprint.sha256Hex(consumerSource) == "1086b82038b893f5be9cde3a8b29e06852c901cc293a213c7c89e32bde44360d")
        try #require(FileFingerprint.sha256Hex(expected) == "87717503bd3a4dbe3ef3222ee4f29dc3269eb6ee09a617f6a151c5e889247ffc")
        let stdlib = try hex1767StdlibSnapshot(useLibrary: useProducerLibrary)
        defer { stdlib?.expectUnchanged() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("KUU1767_RUNTIME_DIRECTORY \(directory.path)")
        let producerInput = directory.appendingPathComponent("producer.kt")
        let consumerInput = directory.appendingPathComponent("consumer.kt")
        try producerSource.write(to: producerInput)
        try consumerSource.write(to: consumerInput)
        var library: Hex1767ArtifactSnapshot?
        if useProducerLibrary {
            let base = directory.appendingPathComponent("SetterProducer")
            let options = CompilerOptions(
                moduleName: "KUU1767SetterProducer", inputs: [producerInput.path], outputPath: base.path,
                emit: .library, target: TargetTriple.hostDefault(), optLevel: optLevel,
                stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false
            )
            try #require(options.optLevel == optLevel)
            try #require(options.stdlibLibraryPath == stdlib?.directory.path && !options.includeStdlib)
            try #require(!options.allowDefaultStdlibLibrary)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "User library producer")
            library = try hex1767UserLibrarySnapshot(base.appendingPathExtension("kklib"))
        }
        let executable = directory.appendingPathComponent("consumer")
        let inputs = useProducerLibrary ? [consumerInput.path] : [producerInput.path, consumerInput.path]
        let searchPaths = library.map { [$0.directory.path] } ?? []
        let options = CompilerOptions(
            moduleName: "KUU1767SetterConsumer", inputs: inputs, outputPath: executable.path,
            emit: .executable, searchPaths: searchPaths, target: TargetTriple.hostDefault(), optLevel: optLevel,
            stdlibLibraryPath: stdlib?.directory.path, allowDefaultStdlibLibrary: false
        )
        try #require(options.optLevel == optLevel)
        try #require(options.inputs == inputs)
        try #require(options.searchPaths == searchPaths)
        try #require(options.stdlibLibraryPath == stdlib?.directory.path)
        try #require(options.includeStdlib == !useProducerLibrary && !options.allowDefaultStdlibLibrary)
        if useProducerLibrary { try #require(!options.inputs.contains(producerInput.path)) }
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: "Separate consumer")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        let executableHash = FileFingerprint.sha256Hex(try Data(contentsOf: executable))
        let execution = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
        try #require(execution.exitCode == 0, "\(execution.stderr)")
        try #require(execution.stderr.isEmpty)
        try #require(Data(execution.stdout.utf8) == expected)
        try #require(Data(contentsOf: producerInput) == producerSource)
        try #require(Data(contentsOf: consumerInput) == consumerSource)
        try stdlib?.requireUnchanged()
        try library?.requireUnchanged()
        try hex1767CleanupSuccessfulRuntime(
            directory: directory, executable: executable, executableHash: executableHash,
            expected: expected, lane: "KUU1767Setter" + (useProducerLibrary ? "-library" : "-source") + "-O\(optLevel.rawValue)"
        )
    }
}

private func hex1767UserLibrarySnapshot(_ directory: URL) throws -> Hex1767ArtifactSnapshot {
    let manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
    try #require(manifest["moduleName"] as? String == "KUU1767SetterProducer")
    try #require(manifest["formatVersion"] as? Int == 1)
    try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
    let objects = try #require(manifest["objects"] as? [String])
    try #require(!objects.isEmpty)
    for object in objects {
        let data = try Data(contentsOf: directory.appendingPathComponent(object))
        try #require(!data.isEmpty, "The producer must emit actual object code")
    }
    let metadata = try Data(contentsOf: directory.appendingPathComponent("metadata.bin"))
    let records = MetadataDecoder().decode(String(decoding: metadata, as: UTF8.self))
    let owner = "settercontrol1767.SetterBox"
    let box = try #require(records.first { $0.kind == .class && $0.fqName == owner })
    let offsets = try hex1767FieldOffsets(box)
    try #require(Set(offsets.values).count == offsets.count)
    for name in ["value", "optional", "counted"] {
        let property = try #require(records.first { $0.kind == .property && $0.fqName == owner + "." + name })
        try #require(property.propertySetterExternalLinkName?.isEmpty == false)
        try #require(offsets[property.fqName] != nil)
        if name != "counted" { try #require(property.propertyGetterExternalLinkName == nil) }
        else { try #require(property.propertyGetterExternalLinkName?.isEmpty == false) }
    }
    let hashes = try hex1767ArtifactHashes(directory)
    try #require(hashes["manifest.json"] != nil && hashes["metadata.bin"] != nil)
    return Hex1767ArtifactSnapshot(directory: directory, hashes: hashes, completeFileSet: true)
}

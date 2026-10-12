@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    /// Keep every original literal, declaration and assertion byte intact.
    /// O0 exercises both actual stdlib routes; the separate pinned CLI gate
    /// adds O2 without multiplying this focused Backend regression.
    @Test(arguments: [false, true])
    func testGenericNumericInputLiteralRuntime(useStdlibLibrary: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let cases = root.appendingPathComponent("Scripts/diff_cases", isDirectory: true)
        let source = try Data(contentsOf: cases.appendingPathComponent("generic_numeric_input_literals.kt"))
        let expected = try Data(contentsOf: cases.appendingPathComponent("generic_numeric_input_literals.expected"))
        try #require(FileFingerprint.sha256Hex(source)
                     == "0b94772cfa5e11d69aae618be617a199d4935432890dfadd20baeee656676514")
        try #require(FileFingerprint.sha256Hex(expected)
                     == "51aefe1137a973e04d7f9ab09a0ff3cdbadcb471b038cb6c055fba14b6d1743e")

        if useStdlibLibrary { TestStdlibCache.shared.prepare() }
        let library = useStdlibLibrary
            ? try #require(CompilerOptions.defaultStdlibLibraryPath,
                           "Library mode must use the published stdlib artifact") : nil
        if let library {
            var isDirectory: ObjCBool = false
            try #require(FileManager.default.fileExists(atPath: library, isDirectory: &isDirectory)
                         && isDirectory.boolValue)
            let directory = URL(fileURLWithPath: library, isDirectory: true)
            let manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["formatVersion"] as? Int == 1)
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
            let metadata = try Data(contentsOf: directory.appendingPathComponent("metadata.bin"))
            try #require(!metadata.isEmpty)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("original.kt")
        try source.write(to: input)
        let copiedSource = try Data(contentsOf: input)
        try #require(copiedSource == source)
        let executable = directory.appendingPathComponent("original")
        let options = CompilerOptions(
            moduleName: "KUU1769GenericNumericInputs",
            inputs: [input.path], outputPath: executable.path, emit: .executable,
            target: TargetTriple.hostDefault(), optLevel: .O0,
            stdlibLibraryPath: library, allowDefaultStdlibLibrary: false
        )
        try #require(options.stdlibLibraryPath == library)
        try #require(options.includeStdlib == !useStdlibLibrary)
        try #require(!options.allowDefaultStdlibLibrary)
        let result = makeTestDriver().runForTesting(options: options)
        try assertCompilationSucceeded(result)
        let compiledSource = try Data(contentsOf: input)
        try #require(compiledSource == source)
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        let execution = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
        #expect(execution.exitCode == 0)
        // The pinned expected output is ASCII, so comparing the returned UTF8
        // bytes also rejects CRLF, replacement characters and trailing output.
        #expect(Data(execution.stdout.utf8) == expected)
        let executedSource = try Data(contentsOf: input)
        #expect(executedSource == source)
    }
}

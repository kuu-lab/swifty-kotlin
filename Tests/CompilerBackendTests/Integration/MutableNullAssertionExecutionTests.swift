@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct MutableNullAssertionExecutionTests {
    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent(name))
    }

    private func stdlib() throws -> String {
        TestStdlibCache.shared.prepare()
        let path = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
        #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        #expect(manifest["kotlinLanguageVersion"] as? String == "2.3.10")
        return path
    }

    @Test(arguments: [false, true], [0, 2])
    func sourceAndLibraryExecutionPreserveMutableNullAssertion(library: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let artifact = library ? try stdlib() : nil
        let source = try fixture("Scripts/diff_cases/mutable_null_assertion.kt")
        let expected = try fixture("Scripts/diff_cases/mutable_null_assertion.expected")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if completed { try? FileManager.default.removeItem(at: directory) } }
        let input = directory.appendingPathComponent("Contract.kt")
        try source.write(to: input)
        let executable = directory.appendingPathComponent("contract")
        let options = CompilerOptions(
            moduleName: "KUU1773Contract", inputs: [input.path], outputPath: executable.path,
            emit: .executable, target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
        )
        #expect(options.stdlibLibraryPath == artifact)
        #expect(options.includeStdlib == !library)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
        try #require(result.exitCode == 0, "\(result.stderr)")
        try #require(Data(result.stdout.utf8) == expected)
        try #require(try Data(contentsOf: input) == source)
        completed = true
    }

}

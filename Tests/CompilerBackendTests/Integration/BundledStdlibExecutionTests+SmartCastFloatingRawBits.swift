@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testSmartCastFloatingRawBitsReproducer(useArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("smart_cast_floating_raw_bits.kt", file: #filePath),
            expectedOutput: "1067450368\n4608308318706860032\n1067450368\n4608308318706860032\n",
            moduleName: "KUU2069RawBitsReproducer",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }

    // Each lane checks receivers, arguments, returns, generic and nullable
    // boundaries without treating the unstable address-derived output as an oracle.
    @Test(arguments: ["source", "stdlib", "producer"], [0, 2])
    func testSmartCastFloatingRawBitsBoundaries(lane: String, optimization: Int) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let fixtures = root.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/SmartCastFloatingRawBits")
        let producer = fixtures.appendingPathComponent("producer.kt")
        let consumer = fixtures.appendingPathComponent("consumer.kt")
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = lane == "source" ? nil : try testStdlibArtifactPath()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var searchPaths: [String] = []
        if lane == "producer" {
            let base = directory.appendingPathComponent("RawBitsProducer")
            let options = CompilerOptions(
                moduleName: "KUU2069RawBitsProducer", inputs: [producer.path], outputPath: base.path,
                emit: .library, target: TargetTriple.hostDefault(), optLevel: level,
                stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            let library = base.appendingPathExtension("kklib")
            let data = try Data(contentsOf: library.appendingPathComponent("manifest.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let objects = try #require(manifest["objects"] as? [String])
            try #require(!objects.isEmpty)
            for object in objects {
                let objectData = try Data(contentsOf: library.appendingPathComponent(object))
                try #require(!objectData.isEmpty)
            }
            searchPaths = [library.path]
        }
        let executable = directory.appendingPathComponent("consumer")
        let options = CompilerOptions(
            moduleName: "KUU2069RawBitsConsumer",
            inputs: lane == "producer" ? [consumer.path] : [producer.path, consumer.path],
            outputPath: executable.path, emit: .executable, searchPaths: searchPaths,
            target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )
        try #require(options.includeStdlib == (lane == "source"))
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == String(repeating: "true\n", count: 94))
    }
}

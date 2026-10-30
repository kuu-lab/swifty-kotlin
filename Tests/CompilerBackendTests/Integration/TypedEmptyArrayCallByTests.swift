import Foundation
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct TypedEmptyArrayCallByTests {
    @Test(arguments: ["source", "stdlib", "library"], [0, 2])
    func emptyArrayComponentsMatchJVM(mode: String, optimization: Int) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repository.appendingPathComponent("Scripts/diff_cases/reflection_typed_empty_array.kt")
        let source = try String(contentsOf: fixture, encoding: .utf8)
        let expected = try String(contentsOf: fixture.deletingPathExtension().appendingPathExtension("expected"), encoding: .utf8)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = mode == "source" ? nil : try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        var searchPaths: [String] = []
        if mode == "library" {
            let main = try #require(source.range(of: "fun main() {"))
            let producer = directory.appendingPathComponent("producer.kt").path
            let library = directory.appendingPathComponent("EmptyArrayAPI").path
            try ("package emptyarrays\n" + source[..<main.lowerBound]).write(toFile: producer, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "EmptyArrayAPI", inputs: [producer], outputPath: library, emit: .library,
                target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib,
                allowDefaultStdlibLibrary: false
            )))
            let artifact = library + ".kklib"
            let inlineBodies = try FileManager.default.contentsOfDirectory(atPath: artifact + "/inline-kir")
            #expect(inlineBodies.filter { $0.hasSuffix(".kirbin") }.count >= 3)
            searchPaths = [artifact]
            try ("import emptyarrays.*\n" + source[main.lowerBound...]).write(toFile: input, atomically: true, encoding: .utf8)
        } else {
            try source.write(toFile: input, atomically: true, encoding: .utf8)
        }
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "EmptyArrayConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: searchPaths, target: defaultTargetTriple(), optLevel: level,
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expected)
    }
}

import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ClassAnnotationRetentionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/class_annotation_retention.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func runtimeAnnotationsMatchJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("retention.kt").path
        let output = directory.appendingPathComponent("retention").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ClassAnnotationRetention", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func libraryMetadataPreservesRetentionWithoutProducerImports(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = try fixture("kt")
        let boundary = try #require(source.range(of: "fun main() {"))
        let libraryInput = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("RetentionAPI").path
        try String(source[..<boundary.lowerBound]).write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "RetentionAPI", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try ("import retentioncases.*\nimport kotlin.reflect.KClass\nimport kotlin.reflect.typeOf\nimport kotlin.reflect.full.findAnnotation\n" + String(source[boundary.lowerBound...]))
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "RetentionConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }
}

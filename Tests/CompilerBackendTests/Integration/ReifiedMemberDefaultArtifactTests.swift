import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct ReifiedMemberDefaultArtifactTests {
    private let expectedOutput = "[A, B]\n[X, Y, Z]\nString\nInt\n0\nIAE\n0\nIAE\n11\n13\nString:Int\nexplicit:Int:String\n"

    @Test(arguments: [false, true], [0, 2])
    func sourceAndStdlibArtifactPreserveMemberDefaults(fromSource: Bool, optimization: Int) throws {
        let source = try diffCaseSource("reified_member_defaults.kt")
        try compileAndRunKotlin(
            source, expectedOutput: expectedOutput, moduleName: "ReifiedMemberDefaults",
            allowDefaultStdlibLibrary: !fromSource,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    @Test(arguments: [0, 2])
    func libraryProducerAndConsumerPreserveMemberDefaults(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let source = try diffCaseSource("reified_member_defaults.kt")
        let declarations = try #require(source.range(of: "enum class Entry"))
        let producer = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("ReifiedClassEnum").path
        try String(source[..<declarations.lowerBound]).write(toFile: producer, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ReifiedClassEnum", inputs: [producer], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let consumer = directory.appendingPathComponent("consumer.kt").path
        try ("import fixture.*\n" + source[declarations.lowerBound...])
            .write(toFile: consumer, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("consumer").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ReifiedMemberConsumer", inputs: [consumer], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expectedOutput)
    }
}

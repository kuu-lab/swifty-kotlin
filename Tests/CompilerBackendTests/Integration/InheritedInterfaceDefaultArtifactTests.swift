import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct InheritedInterfaceDefaultArtifactTests {
    private let expectedOutput = "impl:ok\nimpl:ok\nimpl:ok\nimpl:named\nimpl:ok\nimpl:base\ngeneric\nexplicit\nmethod\n7\n9!\n"

    @Test(arguments: [false, true], [0, 2])
    func sourceAndStdlibArtifactPreserveInheritedDefaults(fromSource: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            diffCaseSource("default_args_inherited_interface_implementation.kt"),
            expectedOutput: expectedOutput,
            moduleName: "InheritedInterfaceDefaults",
            allowDefaultStdlibLibrary: !fromSource,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    @Test(arguments: [0, 2])
    func separateProducerAndConsumerPreserveDefaultOwner(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let source = try diffCaseSource("default_args_inherited_interface_implementation.kt")
        let main = try #require(source.range(of: "fun main()"))
        let producer = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("InheritedDefaultsApi").path
        try ("package fixture\n" + source[..<main.lowerBound]).write(toFile: producer, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "InheritedDefaultsApi", inputs: [producer], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let consumer = directory.appendingPathComponent("consumer.kt").path
        try ("import fixture.*\n" + source[main.lowerBound...]).write(toFile: consumer, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("consumer").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "InheritedDefaultsConsumer", inputs: [consumer], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expectedOutput)

        let invalidConsumer = directory.appendingPathComponent("invalid.kt").path
        try """
        import fixture.*
        fun warm(): String = LabelLeaf().label()
        fun invalid(): String = LabelImpl().label()
        """.write(toFile: invalidConsumer, atomically: true, encoding: .utf8)
        let rejected = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "InheritedDefaultsInvalidConsumer", inputs: [invalidConsumer],
            outputPath: directory.appendingPathComponent("invalid").path, emit: .library,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        ))
        #expect(rejected.exitCode != 0)
        #expect(rejected.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }
}

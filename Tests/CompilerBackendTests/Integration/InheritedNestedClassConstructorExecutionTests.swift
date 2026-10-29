@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct InheritedNestedClassConstructorExecutionTests {
    private let expectedOutput = "31\n"

    @Test(arguments: [0, 2])
    func sourceModeAllowsUnqualifiedInheritedNestedConstructors(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.kt").path
        try sourceModeProgram.write(toFile: source, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("source-program").path
        let result = try compile(
            input: source,
            moduleName: "InheritedNestedSourceO\(optimization)",
            output: output,
            emit: .executable,
            optimization: optimization,
            stdlib: nil,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(result, context: "source-mode O\(optimization)")
        try assertOutput(of: output)
    }

    @Test(arguments: [0, 2])
    func artifactModeFallsBackToOuterConstructorWhenInheritedNestedConstructorDoesNotApply(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stdlib = try testStdlibArtifactPath()
        let source = directory.appendingPathComponent("source.kt").path
        let program = """
        open class Base { class Entry(val number: Int) }
        class Entry(val text: String)
        class Child : Base() { fun value() = Entry("outer") }
        fun main() { println(Child().value().text) }
        """
        try program.write(toFile: source, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("source-program").path
        let result = try compile(
            input: source,
            moduleName: "InheritedNestedOuterFallbackArtifactO\(optimization)",
            output: output,
            emit: .executable,
            optimization: optimization,
            stdlib: stdlib,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(result, context: "outer constructor fallback O\(optimization)")
        try assertOutput(of: output, expectedOutput: "outer\n")
    }

    @Test(arguments: [0, 2])
    func freshLibraryAllowsSubclassAndRejectsUnrelatedProtectedCall(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Pin the prepared stdlib artifact explicitly for both modules. Supplying
        // this path disables source injection and the default-artifact fallback.
        let stdlib = try testStdlibArtifactPath()
        let producer = directory.appendingPathComponent("producer.kt").path
        try producerSource.write(toFile: producer, atomically: true, encoding: .utf8)
        let libraryBase = directory.appendingPathComponent("InheritedNestedApi").path
        let libraryResult = try compile(
            input: producer,
            moduleName: "InheritedNestedApiO\(optimization)",
            output: libraryBase,
            emit: .library,
            optimization: optimization,
            stdlib: stdlib,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(libraryResult, context: "producer O\(optimization)")
        let library = libraryBase + ".kklib"
        #expect(FileManager.default.fileExists(atPath: library))

        let consumer = directory.appendingPathComponent("consumer.kt").path
        try consumerSource.write(toFile: consumer, atomically: true, encoding: .utf8)
        let consumerOutput = directory.appendingPathComponent("consumer").path
        let consumerResult = try compile(
            input: consumer,
            moduleName: "InheritedNestedConsumerO\(optimization)",
            output: consumerOutput,
            emit: .executable,
            optimization: optimization,
            stdlib: stdlib,
            allowDefaultStdlibLibrary: false,
            searchPaths: [library]
        )
        try assertCompilationSucceeded(consumerResult, context: "consumer O\(optimization)")
        try assertOutput(of: consumerOutput)

        let unrelated = directory.appendingPathComponent("unrelated.kt").path
        try unrelatedConsumerSource.write(toFile: unrelated, atomically: true, encoding: .utf8)
        let rejected = try compile(
            input: unrelated,
            moduleName: "UnrelatedNestedConsumerO\(optimization)",
            output: directory.appendingPathComponent("unrelated").path,
            emit: .library,
            optimization: optimization,
            stdlib: stdlib,
            allowDefaultStdlibLibrary: false,
            searchPaths: [library]
        )
        #expect(rejected.exitCode != 0, "An unrelated class must not call the protected nested constructor")
        #expect(rejected.diagnostics.contains {
            $0.severity == .error
                && ($0.code == "KSWIFTK-SEMA-0023" || $0.code == "KSWIFTK-SEMA-0041")
                && $0.message.contains("ProtectedNode")
        }, "Expected a protected/unresolved diagnostic for ProtectedNode, got: \(rejected.diagnostics)")
    }

    private var producerSource: String {
        """
        package fixture

        open class TreeBuilder {
            class PublicNode(val value: Int)
            protected class ProtectedNode(val value: Int)
        }
        """
    }

    private var consumerSource: String {
        """
        package consumer
        import fixture.TreeBuilder

        class Child : TreeBuilder() {
            fun value(): Int = ProtectedNode(7).value + PublicNode(11).value + TreeBuilder.PublicNode(13).value
        }

        fun main() {
            println(Child().value())
        }
        """
    }

    private var unrelatedConsumerSource: String {
        """
        package consumer
        import fixture.TreeBuilder

        class Unrelated {
            fun failIfVisible(): Int = ProtectedNode(1).value
        }
        """
    }

    private var sourceModeProgram: String {
        """
        package fixture

        open class TreeBuilder {
            class PublicNode(val value: Int)
            protected class ProtectedNode(val value: Int)
        }

        class Child : TreeBuilder() {
            fun value(): Int = ProtectedNode(7).value + PublicNode(11).value + TreeBuilder.PublicNode(13).value
        }

        fun main() {
            println(Child().value())
        }
        """
    }

    private func compile(
        input: String,
        moduleName: String,
        output: String,
        emit: EmitMode,
        optimization: Int,
        stdlib: String?,
        allowDefaultStdlibLibrary: Bool,
        searchPaths: [String] = []
    ) throws -> (exitCode: Int, diagnostics: [Diagnostic]) {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [input],
            outputPath: output,
            emit: emit,
            searchPaths: searchPaths,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: true,
            stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
        return makeTestDriver().runForTesting(options: options)
    }

    private func assertOutput(of executable: String, expectedOutput: String? = nil) throws {
        let result = try CommandRunner.run(executable: executable, arguments: [])
        let expected = expectedOutput ?? self.expectedOutput
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
    }
}

import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationJsonPrimitiveTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_json_primitive.\(suffix)"), encoding: .utf8)
    }

    // Source-mode O2 also compiles the entire bundled stdlib at O2; that lane is blocked by KUU-2241.
    @Test(arguments: [(false, 0), (false, 2), (true, 0)])
    func primitiveValuesMatchPublishedJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("primitive.kt").path
        let output = directory.appendingPathComponent("primitive").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "SerializationJsonPrimitive", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func publicPrimitiveValuesCrossSeparateKlib(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let producer = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("JsonPrimitiveProducer").path
        try """
        package producer
        import kotlinx.serialization.json.*
        fun exportedPrimitive(): JsonPrimitive = JsonPrimitive("from producer")
        fun exportedNull(): JsonNull = JsonNull
        """.write(toFile: producer, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "JsonPrimitiveProducer", inputs: [producer], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))

        let consumer = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try """
        import kotlinx.serialization.json.*
        import producer.*
        fun main() {
            val value = exportedPrimitive()
            check(value.isString && value.content == "from producer")
            check(value.toString() == "\\\"from producer\\\"")
            check(exportedNull() === JsonNull)
            println("klib:" + value + ":" + exportedNull())
        }
        """.write(toFile: consumer, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "JsonPrimitiveConsumer", inputs: [consumer], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level,
            stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "klib:\"from producer\":null\n")
    }

    @Test(arguments: [false, true])
    func implementationClassRemainsInternal(fromSource: Bool) throws {
        let input = "/tmp/json-primitive-internal-\(UUID().uuidString).kt"
        let source = "fun main() { kotlinx.serialization.json.JsonLiteral(\"hidden\", true) }"
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "JsonPrimitiveInternalBoundary", inputs: [input], outputPath: "/tmp/json-primitive-internal",
            emit: .executable, target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
        #expect(context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}

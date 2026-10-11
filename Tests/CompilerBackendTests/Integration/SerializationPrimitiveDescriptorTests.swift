import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationPrimitiveDescriptorTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_primitive_descriptor.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func primitiveContractsMatchPublishedJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("primitive.kt").path
        let output = directory.appendingPathComponent("primitive").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PrimitiveDescriptor", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func libraryPreservesFactoryAndDescriptorDispatch(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let source = try fixture("kt")
        let main = try #require(source.range(of: "fun main() {"))
        let declarations = String(source[..<main.lowerBound]).replacingOccurrences(
            of: "\n\nimport kotlinx.serialization.descriptors.*", with: "\n\npackage downstream\n\nimport kotlinx.serialization.descriptors.*"
        )
        let libraryInput = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("PrimitiveAPI").path
        try declarations.write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PrimitiveAPI", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try ("@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\nimport downstream.*\n" + source[main.lowerBound...])
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PrimitiveConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: ["nullName", "nullKind", "structureKind", "internalDescriptor", "internalNameCheck"], [false, true])
    func invalidArgumentsAndInternalAPIsAreRejected(_ mode: String, fromSource: Bool) throws {
        let arguments = switch mode {
        case "nullName": "null, PrimitiveKind.STRING"
        case "nullKind": "\"custom\", null"
        default: "\"custom\", StructureKind.CLASS"
        }
        let call = switch mode {
        case "internalDescriptor": "kotlinx.serialization.internal.PrimitiveSerialDescriptor(\"custom\", PrimitiveKind.STRING)"
        case "internalNameCheck": "kotlinx.serialization.descriptors.checkNameIsNotAPrimitive(\"custom\")"
        default: "PrimitiveSerialDescriptor(\(arguments))"
        }
        let input = "/tmp/primitive-sema-\(UUID().uuidString).kt"
        let source = "@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\nfun main() { \(call) }"
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "InvalidPrimitive", inputs: [input], outputPath: "/tmp/invalid-primitive", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
        #expect(context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [0, 2])
    func importedCatchPreservesThrowableMessageABI(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/reference_cases/imported_throwable_message.kt"
        ), encoding: .utf8)
        let main = try #require(source.range(of: "fun main() {"))
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let libraryInput = directory.appendingPathComponent("messages.kt").path
        let library = directory.appendingPathComponent("Messages").path
        try ("package messages\n" + source[..<main.lowerBound])
            .write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "Messages", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try ("import messages.*\n" + source[main.lowerBound...])
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "MessageConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "ordinary\noverride\nnull\nunrelated override\n")
    }
}

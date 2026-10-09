@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct SerializationDescriptorTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_descriptor.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func interfaceDefaultsOverridesAndIterablesMatchTheJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("descriptor.kt").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("descriptor").path
        let options = CompilerOptions(
            moduleName: "Descriptor", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func aSeparateLibraryPreservesInterfaceAndIteratorDispatch(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        func compile(_ source: String, module: String, emit: EmitMode, libraries: [String] = []) throws -> String {
            let input = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: input, atomically: true, encoding: .utf8)
            let options = CompilerOptions(moduleName: module, inputs: [input], outputPath: output,
                                          emit: emit, searchPaths: libraries, target: defaultTargetTriple(),
                                          optLevel: level, stdlibLibraryPath: stdlib)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? output + ".kklib" : output
        }
        let source = try fixture("kt")
        let mainRange = try #require(source.range(of: "fun main() {"))
        let declarations = String(source[..<mainRange.lowerBound])
            .replacingOccurrences(of: "\n\nimport kotlinx.serialization.descriptors.*", with: "\n\npackage downstream\n\nimport kotlinx.serialization.descriptors.*")
        let library = try compile(declarations + "\nfun provideDescriptor(): Descriptor = EnvelopeDescriptor()\n",
                                  module: "DescriptorLibrary", emit: .library)
        let classRange = try #require(source.range(of: "annotation class DescriptorTag"))
        let header = String(source[..<classRange.lowerBound]).replacingOccurrences(
            of: "@file:OptIn(kotlinx.serialization.SealedSerializationApi::class)", with: ""
        )
        let main = String(source[mainRange.lowerBound...])
            .replacingOccurrences(of: "EnvelopeDescriptor()", with: "downstream.provideDescriptor()")
            .replacingOccurrences(of: "as DescriptorTag", with: "as downstream.DescriptorTag")
        let output = try compile(header + main, module: "DescriptorConsumer", emit: .executable, libraries: [library])
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [false, true], [false, true])
    func subclassOptInIsPreservedThroughSourceAndPrebuilt(fromSource: Bool, optedIn: Bool) throws {
        let input = "/tmp/descriptor-markers-\(UUID().uuidString).kt"
        let source = try fixture("kt").replacingOccurrences(
            of: "@file:OptIn(kotlinx.serialization.SealedSerializationApi::class)",
            with: optedIn ? "@file:OptIn(kotlinx.serialization.SealedSerializationApi::class)" : ""
        )
        let options = CompilerOptions(moduleName: "DescriptorSema", inputs: [input], outputPath: "/tmp/descriptor-sema",
                                      emit: .executable, target: defaultTargetTriple(),
                                      stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
                                      allowDefaultStdlibLibrary: !fromSource)
        let context = CompilerDriver().runFrontend(options: options, inMemorySources: [input: Data(source.utf8)]).context
        let diagnostics = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-SUBCLASS-OPT-IN" }
        #expect(diagnostics.count == (optedIn ? 0 : 2), "\(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == .error && $0.message.contains("SealedSerializationApi") })
        #expect(context.diagnostics.hasError == !optedIn, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [0, 2])
    func capturedInterfacePropertiesUseTheSelectedReceiver(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("captured-property").path
        let input = repository.appendingPathComponent("Scripts/diff_cases/captured_interface_property_receiver.kt").path
        let options = CompilerOptions(
            moduleName: "CapturedProperty", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: try testStdlibArtifactPath()
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "2:2:2:7:100\n4\n5\n9:9:9:7:100\n11\n12\n")
    }
}

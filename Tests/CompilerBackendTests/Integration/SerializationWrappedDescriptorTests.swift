import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationWrappedDescriptorTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_wrapped_descriptor.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func renamedContractsMatchPublishedJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("renamed.kt").path
        let output = directory.appendingPathComponent("renamed").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "RenamedDescriptor", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func libraryPreservesRenamedDescriptorDispatch(optimization: Int) throws {
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
        let library = directory.appendingPathComponent("RenamedAPI").path
        try (declarations + "\nfun exportRenamedDescriptor(original: SerialDescriptor): SerialDescriptor = SerialDescriptor(\"Alias.Library\", original)\n")
            .write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "RenamedAPI", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let consumer = String(source[main.lowerBound...]).replacingOccurrences(of: "fun main() {", with: """
        fun main() {
            val exportedOriginal = WrappedInput("Library")
            val exported = exportRenamedDescriptor(exportedOriginal)
            check(exported.serialName == "Alias.Library")
            check(exported.getElementDescriptor(0) === exportedOriginal.child)
            check(exported.getElementName(0) == "shared")
            exportedOriginal.elementsCount = 3
            check(exported.elementsCount == 3 && exported.getElementName(2) == "third")
            check(exported.toString() == "Alias.Library(shared: custom.Child, shared: custom.Child, third: custom.Child)")
        """)
        try ("@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\nimport downstream.*\n" + consumer)
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "RenamedConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [false, true])
    func stableFactoryNeedsNoCallerOptIn(fromSource: Bool) throws {
        let input = "/tmp/renamed-marker-\(UUID().uuidString).kt"
        let source = "import kotlinx.serialization.descriptors.*\nfun rename(original: SerialDescriptor): SerialDescriptor = SerialDescriptor(original = original, serialName = \"renamed\")"
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "RenamedMarker", inputs: [input], outputPath: "/tmp/renamed-marker", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(!context.diagnostics.diagnostics.contains { $0.message.contains("ExperimentalSerializationApi") }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [0, 2])
    func hiddenClassMembersDoNotPolluteLibraryReceivers(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let library = directory.appendingPathComponent("HiddenAPI").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "HiddenAPI", inputs: [repository.appendingPathComponent("Scripts/reference_cases/hidden_class_metadata_api.kt").path],
            outputPath: library, emit: .library, target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let output = directory.appendingPathComponent("consumer").path
        let compilation = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "HiddenConsumer", inputs: [repository.appendingPathComponent("Scripts/reference_cases/hidden_class_metadata_consumer.kt").path],
            outputPath: output, emit: .executable, searchPaths: [library + ".kklib"], target: defaultTargetTriple(),
            optLevel: level, stdlibLibraryPath: stdlib
        ))
        try assertCompilationSucceeded(compilation)
        #expect(!compilation.diagnostics.contains { $0.code == "KSWIFTK-LIB-0004" }, "\(compilation.diagnostics)")
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "17\n23\n")
    }

    @Test(arguments: [false, true])
    func internalWrapperAndDisplayHelperAreRejected(fromSource: Bool) throws {
        let input = "/tmp/renamed-visibility-\(UUID().uuidString).kt"
        let source = """
        @file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
        import kotlinx.serialization.descriptors.*
        import kotlinx.serialization.descriptors.WrappedSerialDescriptor
        import kotlinx.serialization.internal.toStringImpl
        fun main() {
            val original = PrimitiveSerialDescriptor("custom", PrimitiveKind.STRING)
            WrappedSerialDescriptor("hidden", original)
            original.toStringImpl()
        }
        """
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "RenamedVisibility", inputs: [input], outputPath: "/tmp/renamed-visibility", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
        for hiddenName in ["WrappedSerialDescriptor", "toStringImpl"] {
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0044" && $0.message.contains(hiddenName)
            }, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: ["nullName", "nullOriginal"], [false, true])
    func nonNullFactoryArgumentsAreRequired(_ mode: String, fromSource: Bool) throws {
        let input = "/tmp/renamed-arguments-\(UUID().uuidString).kt"
        let arguments = mode == "nullName" ? "null, PrimitiveSerialDescriptor(\"custom\", PrimitiveKind.STRING)" : "\"renamed\", null"
        let source = "@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\nfun main() { SerialDescriptor(\(arguments)) }"
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "RenamedArguments", inputs: [input], outputPath: "/tmp/renamed-arguments", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
        let callRange = try #require(source.range(of: "SerialDescriptor(\(arguments))"))
        let callOffset = source.utf8.distance(from: source.utf8.startIndex, to: callRange.lowerBound)
        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0002" && $0.primaryRange?.start.offset == callOffset
        }, "\(context.diagnostics.diagnostics)")
    }
}

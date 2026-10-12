import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationNullableDescriptorTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_nullable_descriptor.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func nullableContractsMatchPublishedJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("nullable.kt").path
        let output = directory.appendingPathComponent("nullable").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NullableDescriptor", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func libraryPreservesNullableDescriptorDispatch(optimization: Int) throws {
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
        let library = directory.appendingPathComponent("NullableAPI").path
        try declarations.write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NullableAPI", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try ("@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\nimport downstream.*\n" + source[main.lowerBound...])
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NullableConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func internalNameCachePreservesIdentityAndSnapshots(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Relocate the three internal implementation bodies into a test-only
        // package so their visibility stays internal without colliding with
        // the production declarations already present in the stdlib artifact.
        let paths = [
            "Sources/CompilerCore/Stdlib/kotlinx/serialization/internal/SerialDescriptorForNullable.kt",
            "Sources/CompilerCore/Stdlib/kotlinx/serialization/internal/CachedNames.kt",
            "Sources/CompilerCore/Stdlib/kotlinx/serialization/internal/CachedSerialNames.kt",
            "Scripts/reference_cases/serialization_nullable_descriptor_cache.kt",
        ]
        let inputs = try paths.map { relative in
            let original = try String(contentsOf: repository.appendingPathComponent(relative), encoding: .utf8)
            let source = original.replacingOccurrences(
                of: "package kotlinx.serialization.internal", with: "package nullable.contract"
            )
            let input = directory.appendingPathComponent(URL(fileURLWithPath: relative).lastPathComponent).path
            try source.write(toFile: input, atomically: true, encoding: .utf8)
            return input
        }
        let output = directory.appendingPathComponent("cache-contract").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NullableCacheUnit", inputs: inputs, outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: try testStdlibArtifactPath()
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "fast-path:same-set:no-name-reads\nfallback:deduplicated:stable-snapshot\n")
    }

    @Test(arguments: [0, 2])
    func implicitReceiverAndMultilineDelegationRegression(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = repository.appendingPathComponent("Scripts/reference_cases/implicit_receiver_smartcast_delegation.kt").path
        let output = directory.appendingPathComponent("regression").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ImplicitReceiverRegression", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: try testStdlibArtifactPath()
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "namesoriginal\nnames\nplain\noriginal\n7\ninner\nnames\nplain\n")
    }

    @Test(arguments: [0, 2])
    func libraryDelegationPreservesOverriddenDefaultGetters(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let library = directory.appendingPathComponent("DelegatedGetters").path
        let api = repository.appendingPathComponent("Scripts/reference_cases/class_delegation_default_getter_api.kt").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "DelegatedGetters", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = repository.appendingPathComponent("Scripts/reference_cases/class_delegation_default_getter_consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "DelegatedGetterConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "true\ntrue\ntrue\nfalse\nfalse\nfalse\ntrue\n")
    }

    @Test(arguments: [0, 2])
    func libraryDelegationPreservesFutureMethodsAndExceptions(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let contract = directory.appendingPathComponent("DelegatedContract").path
        let contractInput = repository.appendingPathComponent("Scripts/reference_cases/class_delegation_library_methods_contract.kt").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "DelegatedContract", inputs: [contractInput], outputPath: contract, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let library = directory.appendingPathComponent("DelegatedMethods").path
        let api = repository.appendingPathComponent("Scripts/reference_cases/class_delegation_library_methods_api.kt").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "DelegatedMethods", inputs: [api], outputPath: library, emit: .library,
            searchPaths: [contract + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = repository.appendingPathComponent("Scripts/reference_cases/class_delegation_library_methods_consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "DelegatedMethodConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [contract + ".kklib", library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "consumer\nconsumer\nconsumer\n42\n43\n44\nchanged\nchanged\nknown\nconsumer failure\n")
    }

    @Test(arguments: [0, 2])
    func delegatedSourceMethodPreservesParameterNames(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = repository.appendingPathComponent("Scripts/reference_cases/class_delegation_parameter_names.kt").path
        let output = directory.appendingPathComponent("named-delegation").path
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NamedDelegation", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: try testStdlibArtifactPath()
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "3\n")
    }

    @Test(arguments: [false, true])
    func internalWrapperConstructorIsRejected(fromSource: Bool) throws {
        let input = "/tmp/nullable-wrapper-visibility-\(UUID().uuidString).kt"
        let source = """
        @file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
        import kotlinx.serialization.descriptors.*
        import kotlinx.serialization.internal.SerialDescriptorForNullable
        fun main() { SerialDescriptorForNullable(PrimitiveSerialDescriptor("custom", PrimitiveKind.STRING)) }
        """
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "NullableWrapperVisibility", inputs: [input], outputPath: "/tmp/nullable-wrapper-visibility", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0044" && $0.message.contains("SerialDescriptorForNullable")
        }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: ["marker", "helper", "parameter", "return", "generic", "alias"], [false, true])
    func internalNullableAPIsAreRejected(_ mode: String, fromSource: Bool) throws {
        let extraImport = mode == "helper" ? "import kotlinx.serialization.internal.cachedSerialNames\n" : ""
        let declarations = switch mode {
        case "marker": "fun main() { val names: kotlinx.serialization.internal.CachedNames? = null }"
        case "helper": "fun main() { PrimitiveSerialDescriptor(\"custom\", PrimitiveKind.STRING).cachedSerialNames() }"
        case "parameter": "fun inspect(value: kotlinx.serialization.internal.CachedNames?) {}"
        case "return": "fun inspect(): kotlinx.serialization.internal.CachedNames? = null"
        case "generic": "fun inspect(value: List<kotlinx.serialization.internal.CachedNames?>) {}"
        default: "typealias Names = kotlinx.serialization.internal.CachedNames"
        }
        let input = "/tmp/nullable-visibility-\(UUID().uuidString).kt"
        let source = "@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\n" + extraImport + declarations
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "NullableVisibility", inputs: [input], outputPath: "/tmp/nullable-visibility", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
        let hiddenName = mode == "helper" ? "cachedSerialNames" : "CachedNames"
        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0044" && $0.message.contains(hiddenName)
        }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true], [false, true])
    func nonNullOriginalRetainsExperimentalMarker(fromSource: Bool, optedIn: Bool) throws {
        let input = "/tmp/nullable-marker-\(UUID().uuidString).kt"
        let annotation = optedIn ? "@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\n" : ""
        let source = annotation + "import kotlinx.serialization.descriptors.*\nfun unwrap(value: SerialDescriptor): SerialDescriptor = value.nonNullOriginal\nfun wrap(value: SerialDescriptor): SerialDescriptor = value.nullable"
        let context = CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "NullableMarker", inputs: [input], outputPath: "/tmp/nullable-marker", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
        let diagnostics = context.diagnostics.diagnostics.filter { $0.message.contains("ExperimentalSerializationApi") }
        #expect(diagnostics.count == (optedIn ? 0 : 1), "\(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == .warning }, "\(diagnostics)")
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}

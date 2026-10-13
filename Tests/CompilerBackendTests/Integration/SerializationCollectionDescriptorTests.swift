import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationCollectionDescriptorTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_collection_descriptor.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func collectionContractsMatchPublishedJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("collections.kt").path
        let output = directory.appendingPathComponent("collections").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "CollectionDescriptor", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func libraryPreservesProducerCreatedCollections(optimization: Int) throws {
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
        let library = directory.appendingPathComponent("CollectionAPI").path
        try (declarations + "\nfun exportCollections(original: SerialDescriptor): List<SerialDescriptor> = listOf(listSerialDescriptor(original), setSerialDescriptor(original), mapSerialDescriptor(original, original.nullable))\n")
            .write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "CollectionAPI", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let consumer = String(source[main.lowerBound...]).replacingOccurrences(of: "fun main() {", with: """
        fun main() {
            val exportedOriginal = MutableChild(PrimitiveSerialDescriptor("Library", PrimitiveKind.STRING))
            val exported = exportCollections(exportedOriginal)
            check(exported.size == 3)
            check(exported[0].serialName == "kotlin.collections.ArrayList")
            check(exported[1].serialName == "kotlin.collections.HashSet")
            check(exported[2].serialName == "kotlin.collections.HashMap")
            check(exported[0].getElementDescriptor(7) === exportedOriginal)
            check(exported[1].getElementDescriptor(7) === exportedOriginal)
            check(exported[2].getElementDescriptor(4) === exportedOriginal)
            check(exported[2].getElementDescriptor(5).nonNullOriginal === exportedOriginal)
            val oldHash = exported[0].hashCode()
            exportedOriginal.hash = Int.MAX_VALUE
            check(exported[0].hashCode() != oldHash)
        """)
        try ("@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\nimport downstream.*\n" + consumer)
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "CollectionConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [false, true], [false, true])
    func factoriesRetainExperimentalMarker(fromSource: Bool, optedIn: Bool) throws {
        let input = "/tmp/collection-marker-\(UUID().uuidString).kt"
        let annotation = optedIn ? "@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\n" : ""
        let source = annotation + """
        import kotlinx.serialization.descriptors.*
        fun list(value: SerialDescriptor): SerialDescriptor = listSerialDescriptor(value)
        fun set(value: SerialDescriptor): SerialDescriptor = setSerialDescriptor(value)
        fun map(value: SerialDescriptor): SerialDescriptor = mapSerialDescriptor(value, value)
        """
        let context = try frontend(source, input: input, fromSource: fromSource)
        let diagnostics = context.diagnostics.diagnostics.filter { $0.message.contains("ExperimentalSerializationApi") }
        #expect(diagnostics.count == (optedIn ? 0 : 3), "\(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == .warning }, "\(diagnostics)")
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func internalConstructorsAreRejected(fromSource: Bool) throws {
        let input = "/tmp/collection-visibility-\(UUID().uuidString).kt"
        let source = """
        @file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
        import kotlinx.serialization.descriptors.*
        import kotlinx.serialization.internal.ArrayListClassDesc
        import kotlinx.serialization.internal.HashSetClassDesc
        import kotlinx.serialization.internal.HashMapClassDesc
        fun main() {
            val original = PrimitiveSerialDescriptor("custom", PrimitiveKind.STRING)
            ArrayListClassDesc(original)
            HashSetClassDesc(original)
            HashMapClassDesc(original, original)
        }
        """
        let context = try frontend(source, input: input, fromSource: fromSource)
        for name in ["ArrayListClassDesc", "HashSetClassDesc", "HashMapClassDesc"] {
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0044" && $0.message.contains(name)
            }, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func internalBaseTypesAreRejected(fromSource: Bool) throws {
        let input = "/tmp/collection-types-\(UUID().uuidString).kt"
        let source = """
        import kotlinx.serialization.internal.ListLikeDescriptor
        import kotlinx.serialization.internal.MapLikeDescriptor
        fun inspectList(value: ListLikeDescriptor) {}
        fun inspectMap(value: MapLikeDescriptor) {}
        """
        let context = try frontend(source, input: input, fromSource: fromSource)
        for name in ["ListLikeDescriptor", "MapLikeDescriptor"] {
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0044" && $0.message.contains(name)
            }, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func factoriesRequireNonNullDescriptors(fromSource: Bool) throws {
        let input = "/tmp/collection-arguments-\(UUID().uuidString).kt"
        let calls = ["listSerialDescriptor(null)", "setSerialDescriptor(null)",
                     "mapSerialDescriptor(null, original)", "mapSerialDescriptor(original, null)"]
        let source = "@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\nfun main() { val original = PrimitiveSerialDescriptor(\"custom\", PrimitiveKind.STRING); " + calls.joined(separator: "; ") + " }"
        let context = try frontend(source, input: input, fromSource: fromSource)
        for call in calls {
            let range = try #require(source.range(of: call))
            let offset = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0002" && $0.primaryRange?.start.offset == offset
            }, "\(context.diagnostics.diagnostics)")
        }
    }

    private func frontend(_ source: String, input: String, fromSource: Bool) throws -> CompilationContext {
        CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "CollectionContract", inputs: [input], outputPath: "/tmp/collection-contract", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
    }
}

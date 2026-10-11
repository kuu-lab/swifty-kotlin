@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct SerializationKindsTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_kinds.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func allKindsMatchTheJVMReference(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("kinds.kt").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("kinds").path
        let options = CompilerOptions(
            moduleName: "Kinds", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func aSeparateLibraryPreservesKindIdentityDispatchAndType(optimization: Int) throws {
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
        let library = try compile("""
        package downstream
        import kotlinx.serialization.descriptors.*
        fun provideKind(): SerialKind = PrimitiveKind.INT
        fun describeKind(kind: SerialKind): String = kind.toString()
        fun hashKind(kind: SerialKind): Int = kind.hashCode()
        fun isPrimitive(kind: SerialKind): Boolean = kind is PrimitiveKind
        """, module: "KindsLibrary", emit: .library)
        let consumer = try fixture("kt").replacingOccurrences(of: "fun main() {", with: """
        fun main() {
            val imported = downstream.provideKind()
            check(imported === Primitive.INT)
            check(downstream.describeKind(imported) == "INT")
            check(downstream.hashKind(imported) == "INT".hashCode())
            check(downstream.isPrimitive(imported))
            check(!downstream.isPrimitive(StructureKind.CLASS))
        """)
        let output = try compile(consumer, module: "KindsConsumer", emit: .executable, libraries: [library])
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: ["external", "kotlinx.serialization.descriptors"], [false, true])
    func prebuiltSealedKindRejectsAnExternalSubclass(packageName: String, nested: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let input = directory.appendingPathComponent("bad.kt").path
        let options = CompilerOptions(moduleName: "BadKinds", inputs: [input], outputPath: directory.path,
                                      emit: .executable, target: defaultTargetTriple(), stdlibLibraryPath: try testStdlibArtifactPath())
        let context = CompilerDriver().runFrontend(options: options, inMemorySources: [input: Data("""
        package \(packageName)
        import kotlinx.serialization.descriptors.SerialKind
        \(nested ? "class Holder { class Bad: SerialKind() }" : "class Bad: SerialKind()")
        """.utf8)]).context
        #expect(context.diagnostics.diagnostics.contains { $0.message.contains("sealed subclasses must be in the same module") })
    }

    @Test
    func prebuiltApiMarkersPreserveTargetsSeverityAndConcatenatedMessage() throws {
        let input = "/tmp/serialization-markers-\(UUID().uuidString).kt"
        let options = CompilerOptions(moduleName: "Markers", inputs: [input], outputPath: "/tmp/markers",
                                      emit: .executable, target: defaultTargetTriple(), stdlibLibraryPath: try testStdlibArtifactPath())
        let context = CompilerDriver().runFrontend(options: options, inMemorySources: [input: Data("""
        import kotlinx.serialization.*
        @ExperimentalSerializationApi fun experimentalApi() {}
        @InternalSerializationApi fun internalApi() {}
        fun caller() { experimentalApi(); internalApi() }
        @SubclassOptInRequired(SealedSerializationApi::class) open class Contract
        class Child: Contract()
        @SealedSerializationApi class InvalidTarget
        """.utf8)]).context
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning && $0.message.contains("ExperimentalSerializationApi") })
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error && $0.message.contains("InternalSerializationApi") })
        let message = "This class or interface should not be inherited/implemented outside of kotlinx.serialization library. " +
            "Note it is still permitted to use it directly. Read its documentation about inheritance for details."
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-SUBCLASS-OPT-IN" && $0.severity == .error && $0.message.hasSuffix(message) })
        #expect(diagnostics.contains { $0.message.contains("not applicable") })
    }
}

import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationClassDescriptorTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_class_descriptor.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func builderContractsMatchPublishedJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("builder.kt").path
        let output = directory.appendingPathComponent("builder").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ClassDescriptor", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func libraryPreservesProducerCreatedDescriptorsAndErrors(optimization: Int) throws {
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
        let library = directory.appendingPathComponent("ClassDescriptorAPI").path
        try (declarations + """
        \nfun exportRecord(original: SerialDescriptor): SerialDescriptor = buildClassSerialDescriptor("Library", original) {
            element("fromProducer", original, isOptional = true)
            annotations = listOf(BuilderTag("library"))
        }
        fun exportDuplicate(original: SerialDescriptor): SerialDescriptor = buildClassSerialDescriptor("Library") {
            element("x", original); element("x", original)
        }
        """).write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ClassDescriptorAPI", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let consumer = String(source[main.lowerBound...]).replacingOccurrences(of: "fun main() {", with: """
        fun main() {
            val original = PrimitiveSerialDescriptor("LibraryChild", PrimitiveKind.STRING)
            val exported = exportRecord(original)
            check(exported.serialName == "Library" && exported.kind === StructureKind.CLASS)
            check(exported.elementsCount == 1 && exported.getElementName(0) == "fromProducer")
            check(exported.getElementIndex("fromProducer") == 0 && exported.getElementIndex("missing") == -3)
            check(exported.getElementDescriptor(0) === original && exported.isElementOptional(0))
            check(exported.annotations.single() == BuilderTag("library"))
            check(exported.toString() == "Library(fromProducer: LibraryChild)")
            val local = buildClassSerialDescriptor("Library", original) { element("localName", original) }
            check(exported == local && exported.hashCode() == local.hashCode())
            checkBounds(exported)
            invalidBuilder({ exportDuplicate(original) }, "Element with name 'x' is already registered in Library")
        """)
        try ("@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.InternalSerializationApi::class, kotlinx.serialization.SealedSerializationApi::class)\n@file:Suppress(\"DEPRECATION_ERROR\")\nimport kotlinx.serialization.descriptors.*\nimport downstream.*\n" + consumer)
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ClassDescriptorConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [false, true])
    func sourceVisibilityAndMarkersArePreserved(fromSource: Bool) throws {
        let source = """
        import kotlinx.serialization.descriptors.*
        fun stable(value: SerialDescriptor): SerialDescriptor = buildClassSerialDescriptor("Stable") { element("value", value) }
        fun inspect(builder: ClassSerialDescriptorBuilder) {
            buildSerialDescriptor("Custom", StructureKind.LIST)
            builder.annotations = emptyList()
            val annotations = builder.annotations
            builder.isNullable = true
            val nullable = builder.isNullable
        }
        fun implicit() = buildClassSerialDescriptor("Implicit") { isNullable = true }
        fun hidden(value: SerialDescriptorImpl) {}
        fun invalidConstructor() = ClassSerialDescriptorBuilder("Hidden")
        """
        let context = try frontend(source, fromSource: fromSource)
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error && $0.message.contains("InternalSerializationApi") }, "\(diagnostics)")
        #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning && $0.message.contains("ExperimentalSerializationApi") }, "\(diagnostics)")
        #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" && $0.severity == .error && $0.message.contains("isNullable") }.count == 3, "\(diagnostics)")
        for name in ["SerialDescriptorImpl", "ClassSerialDescriptorBuilder"] {
            #expect(diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" && $0.severity == .error && $0.message.contains(name) }, "\(diagnostics)")
        }
        let sema = try #require(context.sema)
        let builder = ["kotlinx", "serialization", "descriptors", "ClassSerialDescriptorBuilder"]
        let builderSymbol = try #require(sema.symbols.lookup(fqName: builder.map(context.interner.intern)))
        #expect(sema.symbols.symbol(builderSymbol)?.visibility == .public)
        let constructors = sema.symbols.lookupAll(fqName: (builder + ["<init>"]).map(context.interner.intern))
        #expect(!constructors.isEmpty)
        #expect(constructors.allSatisfy { sema.symbols.symbol($0)?.visibility == .internal })
        let stable = sema.symbols.lookupAll(fqName: ["kotlinx", "serialization", "descriptors", "buildClassSerialDescriptor"].map(context.interner.intern))
        #expect(!stable.isEmpty)
        #expect(stable.allSatisfy { !sema.symbols.annotations(for: $0).contains { $0.annotationFQName.hasSuffix("SerializationApi") } })
    }

    @Test(arguments: [false, true])
    func optedInAndSuppressedCompatibilityPropertyRemainsUsable(fromSource: Bool) throws {
        let source = """
        @file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class, kotlinx.serialization.InternalSerializationApi::class)
        @file:Suppress("DEPRECATION_ERROR")
        import kotlinx.serialization.descriptors.*
        fun build(value: SerialDescriptor): SerialDescriptor = buildClassSerialDescriptor("Stable") {
            annotations = emptyList(); isNullable = true
            check(isNullable); element("value", value)
        }
        fun custom() = buildSerialDescriptor("Custom", StructureKind.OBJECT)
        """
        let context = try frontend(source, fromSource: fromSource)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(!context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" || $0.code == "KSWIFTK-SEMA-DEPRECATED" }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func factoriesAndElementRequireNonNullArguments(fromSource: Bool) throws {
        let calls = ["buildClassSerialDescriptor(null)", "buildClassSerialDescriptor(\"Typed\", null)",
                     "buildSerialDescriptor(\"Custom\", null)", "builder.element(\"child\", null)",
                     "builder.element(\"child\", value, annotations = null)"]
        let source = "@file:OptIn(kotlinx.serialization.InternalSerializationApi::class)\nimport kotlinx.serialization.descriptors.*\nfun invalid(builder: ClassSerialDescriptorBuilder, value: SerialDescriptor) { " + calls.joined(separator: "; ") + " }"
        let context = try frontend(source, fromSource: fromSource)
        for call in calls {
            let range = try #require(source.range(of: call))
            let offset = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
            #expect(context.diagnostics.diagnostics.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0002" && $0.primaryRange?.start.offset == offset }, "\(context.diagnostics.diagnostics)")
        }
    }

    private func frontend(_ source: String, fromSource: Bool) throws -> CompilationContext {
        let input = "/tmp/class-descriptor-contract-\(UUID().uuidString).kt"
        return CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "ClassDescriptorContract", inputs: [input], outputPath: "/tmp/class-descriptor-contract", emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: [input: Data(source.utf8)]).context
    }
}

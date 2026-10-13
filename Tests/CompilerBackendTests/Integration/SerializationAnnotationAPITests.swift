import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationAnnotationAPITests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_annotation_api.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func sourceAPIsMatchPublishedJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("retention.kt").path
        let output = directory.appendingPathComponent("retention").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "SerializationAnnotationAPI", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func libraryPreservesTypedAnnotationsAndBinaryMetadata(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = try fixture("kt")
        let boundary = try #require(source.range(of: "fun main() {"))
        let libraryInput = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("SerializationAnnotationAPIProducer").path
        let declarations = String(source[..<boundary.lowerBound]).replacingOccurrences(
            of: "import kotlinx.serialization.*", with: "package producer\n\nimport kotlinx.serialization.*\nimport kotlinx.serialization.SerialName as WireName"
        ).replacingOccurrences(of: "@SerialName(\"wire.Record\")", with: "@WireName(\"wire.Record\")")
        try (declarations + """
        \nfun exportedDescriptor(): SerialDescriptor = buildClassSerialDescriptor("Producer") {
            annotations = listOf(SerialName("wire.Root"), SerialTag("producer"), InheritedTag(11))
            element("declared", PrimitiveSerialDescriptor("ProducerChild", PrimitiveKind.INT),
                    annotations = listOf(SerialName("wire.Field"), SerialTag("element")))
        }
        """).write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "SerializationAnnotationAPIProducer", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let records = MetadataDecoder().decode(try String(contentsOfFile: library + ".kklib/metadata.bin", encoding: .utf8))
        let tag = try #require(records.first { $0.fqName == "producer.SerialTag" })
        let marker = try #require(tag.annotations.first { $0.annotationFQName == "kotlinx.serialization.SerialInfo" })
        #expect(marker.retention == .binary && marker.factoryLinkName == nil)
        #expect(tag.annotations.contains { $0.annotationFQName == "kotlin.annotation.Target" && $0.arguments.contains { $0.contains("PROPERTY") } })
        let inherited = try #require(records.first { $0.fqName == "producer.InheritedTag" })
        #expect(inherited.annotations.contains { $0.annotationFQName == "kotlinx.serialization.InheritableSerialInfo" && $0.retention == .binary })
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try ("@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)\nimport producer.*\nimport kotlinx.serialization.*\nimport kotlinx.serialization.descriptors.*\n" + String(source[boundary.lowerBound...]).replacingOccurrences(of: "fun main() {", with: """
            fun main() {
                val exported = exportedDescriptor()
                check(exported.serialName == "Producer" && exported.getElementName(0) == "declared")
                check(exported.annotations.filterIsInstance<SerialName>().single().value == "wire.Root")
                check(exported.annotations.filterIsInstance<SerialTag>().single() == SerialTag("producer"))
                check(exported.annotations.filterIsInstance<InheritedTag>().single().value == 11)
                check(exported.getElementAnnotations(0).filterIsInstance<SerialName>().single().value == "wire.Field")
                check(exported.getElementAnnotations(0).filterIsInstance<SerialTag>().single().value == "element")
            """))
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "SerializationAnnotationAPIConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: ["WARNING", "ERROR"])
    func importedExperimentalAnnotationsConsumeTheirMarkerAtTheApplicationSite(level: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let producer = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("ExperimentalAnnotationAPI").path
        try """
        package producer
        @RequiresOptIn(level = RequiresOptIn.Level.\(level)) annotation class Marker
        @Marker annotation class Meta
        @OptIn(Marker::class) @Meta annotation class Tag(val value: String)
        @OptIn(Marker::class) @Meta fun stable(): Int = 1
        @Marker fun experimental(): Int = 2
        """.write(toFile: producer, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ExperimentalAnnotationAPI", inputs: [producer], outputPath: library, emit: .library,
            target: defaultTargetTriple(), stdlibLibraryPath: stdlib
        )))
        func frontend(_ source: String) -> CompilationContext {
            let input = directory.appendingPathComponent("consumer.kt").path
            return CompilerDriver().runFrontend(options: CompilerOptions(
                moduleName: "ExperimentalAnnotationConsumer", inputs: [input], outputPath: input + ".out", emit: .executable,
                searchPaths: [library + ".kklib"], target: defaultTargetTriple(), stdlibLibraryPath: stdlib
            ), inMemorySources: [input: Data(source.utf8)]).context
        }
        let safe = frontend("""
        import producer.*
        fun ordinary(value: Tag): Tag { stable(); return Tag(value.value) }
        """)
        #expect(!safe.diagnostics.hasError, "\(safe.diagnostics.diagnostics)")
        #expect(!safe.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" })
        for usage in [
            "@Meta class InvalidSite",
            "fun needsType(value: Meta) {}",
            "fun needsConstructor(): Annotation = Meta()",
            "fun needsFunction(): Int = experimental()",
        ] {
            let invalid = frontend("import producer.*\n" + usage).diagnostics.diagnostics
            #expect(invalid.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == (level == "ERROR" ? .error : .warning) && $0.message.contains("Marker") }, "\(usage): \(invalid)")
        }
    }
}

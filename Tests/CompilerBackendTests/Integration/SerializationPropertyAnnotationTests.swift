import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SerializationPropertyAnnotationTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/serialization_property_annotations.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true])
    func modeTypeAloneRetainsGeneratedEnumHelpers(fromSource: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("mode.kt").path
        let output = directory.appendingPathComponent("mode").path
        try """
        import kotlinx.serialization.EncodeDefault
        fun main() { println(EncodeDefault().mode.name) }
        """.write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PropertyAnnotationModeTypeOnly", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "ALWAYS\n")
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
            moduleName: "SerializationPropertyAnnotations", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func separateProducerPreservesActualPropertyAnnotationObjects(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = try fixture("kt")
        let boundary = try #require(source.range(of: "fun main() {"))
        let producer = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("PropertyAnnotationProducer").path
        try ("package producer\n" + String(source[..<boundary.lowerBound]) + """
        \nprivate val actualAnnotations: List<Annotation> = listOf(Required(), Transient(), EncodeDefault(EncodeDefault.Mode.NEVER))
        fun exportedAnnotations(): List<Annotation> = actualAnnotations
        fun exportedDescriptor(): SerialDescriptor = buildClassSerialDescriptor("Producer") {
            element("declared", PrimitiveSerialDescriptor("Child", PrimitiveKind.INT), annotations = exportedAnnotations())
        }
        """).write(toFile: producer, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PropertyAnnotationProducer", inputs: [producer], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let records = MetadataDecoder().decode(try String(contentsOfFile: library + ".kklib/metadata.bin", encoding: .utf8))
        for (field, annotation) in [("required", "Required"), ("temporary", "Transient"), ("optional", "EncodeDefault")] {
            let record = try #require(records.first { $0.fqName == "producer.FieldModel." + field })
            let stored = try #require(record.annotations.first { $0.annotationFQName == "kotlinx.serialization." + annotation })
            // Legacy-compatible metadata omits the default RUNTIME value.
            #expect(stored.retention == nil || stored.retention == .runtime)
            #expect(stored.factoryLinkName != nil)
        }
        let consumer = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let main = String(source[boundary.lowerBound...]).replacingOccurrences(of: "fun main() {", with: """
        fun main() {
            val exported = exportedAnnotations()
            check(exported.size == 3)
            check(exported[0] is Required && exported[1] is Transient && exported[2] is EncodeDefault)
            check((exported[2] as EncodeDefault).mode === EncodeDefault.Mode.NEVER)
            val fromProducer = exportedDescriptor()
            check(fromProducer.serialName == "Producer" && fromProducer.getElementName(0) == "declared")
            val stored = fromProducer.getElementAnnotations(0)
            check(stored.size == 3 && fromProducer.elementsCount == 1)
            check(stored[0] === exported[0] && stored[1] === exported[1] && stored[2] === exported[2])
            check(stored.filterIsInstance<Required>().single() == Required())
            check(stored.filterIsInstance<Transient>().single() == Transient())
            check(stored.filterIsInstance<EncodeDefault>().single() == EncodeDefault(EncodeDefault.Mode.NEVER))
            check(!fromProducer.isElementOptional(0))
        """)
        try ("import producer.*\nimport kotlinx.serialization.*\nimport kotlinx.serialization.descriptors.*\n" + main)
            .write(toFile: consumer, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PropertyAnnotationConsumer", inputs: [consumer], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }
}

import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct TypedAnnotationReflectionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Scripts/reference_cases/typed_annotation_reflection.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func runtimeAnnotationsMatchJVM(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("retention.kt").path
        let output = directory.appendingPathComponent("retention").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "TypedAnnotationReflection", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func libraryFactoryPreservesProducerConstruction(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = try fixture("kt")
        let boundary = try #require(source.range(of: "fun main() {"))
        let libraryInput = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("AnnotationFactoryAPI").path
        try String(source[..<boundary.lowerBound]).write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "AnnotationFactoryAPI", inputs: [libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let records = MetadataDecoder().decode(try String(contentsOfFile: library + ".kklib/metadata.bin", encoding: .utf8))
        for owner in ["typedannotations.Named", "typedannotations.Carrier.Tag"] {
            for name in ["equals", "hashCode", "toString"] {
                #expect(records.contains { $0.fqName == owner + "." + name && $0.externalLinkName != nil })
                #expect(records.first { $0.fqName == owner }?.vtableSlots?.contains(name) == true)
            }
        }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try ("import typedannotations.*\nimport kotlin.reflect.KClass\nimport kotlin.reflect.typeOf\nimport kotlin.reflect.full.findAnnotation\n" + String(source[boundary.lowerBound...]))
            .write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "AnnotationFactoryConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    @Test(arguments: [0, 2])
    func privateAnnotationFactoriesKeepProducerAliasesAndMetaCycles(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let declarationInput = directory.appendingPathComponent("declarations.kt").path
        let libraryInput = directory.appendingPathComponent("producer.kt").path
        let library = directory.appendingPathComponent("PrivateAnnotationFactories").path
        try """
        package definitions
        annotation class Named(val value: String)
        """.write(toFile: declarationInput, atomically: true, encoding: .utf8)
        try """
        package producer
        import definitions.Named as ProducerName
        import kotlin.reflect.full.findAnnotation
        private annotation class PrivateTag(val value: String = "private default")
        @B annotation class A
        @A annotation class B
        @ProducerName("escaped\\n" + "text") @PrivateTag class Secret
        fun privateValue(): String = Secret::class.annotations.filterIsInstance<PrivateTag>().single().value
        fun cyclic(): Boolean = A::class.findAnnotation<B>() != null && B::class.findAnnotation<A>() != null
        """.write(toFile: libraryInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PrivateAnnotationFactories", inputs: [declarationInput, libraryInput], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try """
        import producer.*
        import definitions.Named
        import kotlin.reflect.full.findAnnotation
        fun main() {
            repeat(2) {
                check(Secret::class.annotations.size == 2)
                check(Secret::class.findAnnotation<Named>()!!.value == "escaped\\ntext")
                check(privateValue() == "private default")
                Secret()
                check(cyclic())
            }
            println("private:alias:escaped:repeated:meta-cycles")
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PrivateFactoryConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "private:alias:escaped:repeated:meta-cycles\n")
    }
}

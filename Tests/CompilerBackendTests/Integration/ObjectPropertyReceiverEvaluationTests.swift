#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ObjectPropertyReceiverEvaluationTests {
    @Test(arguments: [0, 2])
    func explicitReceiverSideEffectsArePreserved(
        optimization: Int
    ) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let source = try diffCaseSource("kuu_2307_object_property_receiver.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "KUU2307ObjectPropertyReceiver",
            expected: "OK",
            optLevel: optLevel,
            allowDefaultStdlibLibrary: true
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func objectAccessorWritesUseTheBackingField(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let source = try diffCaseSource("object_accessor_backing_field_assignment.kt", file: #filePath)
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ObjectAccessorBackingFieldAssignment",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: optLevel,
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        let route = "\(fromSource ? "source" : "fresh artifact"), O\(optimization)"
        #expect(result.exitCode == 0, "\(route): \(result.stderr)")
        #expect(result.stderr.isEmpty, "\(route): \(result.stderr)")
        #expect(result.stdout == """
        getter=2:2
        setter=2:4
        property=2:6
        plain=2:8
        custom=3:1:10
        nullable=2:12
        nullableNull=true:14
        bare=3:14
        compoundGetter=5:16
        compoundSetter=4:18
        compoundPlain=4:20
        compoundCustom=6:2:22
        computed=3:24
        compoundComputed=6:26

        """, "\(route): \(String(reflecting: result.stdout))")
    }
}
#endif

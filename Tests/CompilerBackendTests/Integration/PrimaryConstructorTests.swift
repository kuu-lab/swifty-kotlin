import Foundation
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct PrimaryConstructorTests {
    private func checkFixture(_ name: String, expected: String, fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try diffCaseSource(name, file: #filePath).write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "PrimaryConstructor", inputs: [input], outputPath: output, emit: .executable,
            target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        )))
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expected)
    }

    @Test(arguments: [false, true], [0, 2])
    func originalConstructorCase(fromSource: Bool, optimization: Int) throws {
        try checkFixture(
            "kconstructor_basic.kt",
            expected: "Person constructors count: 1\nPerson has primary constructor: true\nSimple constructors count: 1\nWithSecondary constructors count: 2\n",
            fromSource: fromSource, optimization: optimization
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func publicImportAliasAndTypedCalls(fromSource: Bool, optimization: Int) throws {
        try checkFixture(
            "kclass_primary_constructor.kt",
            expected: "true\n0\ntrue\n2\n1\n42\n1\ntrue\ntrue\ntrue\n[name:true, age:true]\ndefault:7\nchosen:7\ndirect:9\n",
            fromSource: fromSource, optimization: optimization
        )
    }

    @Test(arguments: [false, true])
    func constructorTypeCannotBeAssignedToAnotherClass(fromSource: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("invalid.kt").path
        try """
        import kotlin.reflect.KFunction
        import kotlin.reflect.full.primaryConstructor
        class First
        class Second
        fun main() {
            val wrong: KFunction<Second>? = First::class.primaryConstructor
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "WrongConstructorType", inputs: [input],
            outputPath: directory.appendingPathComponent("invalid").path, emit: .executable,
            target: defaultTargetTriple(),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
        ))
        #expect(result.exitCode != 0)
        #expect(result.diagnostics.contains { $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001" })
    }
}

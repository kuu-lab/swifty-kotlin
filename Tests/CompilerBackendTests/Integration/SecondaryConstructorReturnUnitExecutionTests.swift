#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct SecondaryConstructorReturnUnitExecutionTests {
    @Test
    func returnUnitExitsSecondaryConstructor() throws {
        let source = """
        class A {
            val prop: Int
            constructor(arg: Boolean) {
                if (arg) { prop = 1; return Unit }
                prop = 2
            }
        }
        fun main() {
            println(A(true).prop)
            println(A(false).prop)
        }
        """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("secondary-constructor-return-unit.kt")
        let output = directory.appendingPathComponent("secondary-constructor-return-unit")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: "SecondaryConstructorReturnUnit",
            inputs: [input.path],
            outputPath: output.path,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let execution = try CommandRunner.run(executable: output.path, arguments: [], timeout: 10)
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == "1\n2\n")
        #expect(execution.stderr.isEmpty)
    }
}
#endif

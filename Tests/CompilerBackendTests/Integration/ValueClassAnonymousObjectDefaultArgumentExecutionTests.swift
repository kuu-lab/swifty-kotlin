#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ValueClassAnonymousObjectDefaultArgumentExecutionTests {
    @Test(arguments: [0, 2])
    func nullableUnderlyingValueClassDefaultCanUseAnonymousObject(optimization: Int) throws {
        let source = """
        annotation class JvmInline

        open class FooA(val string: String)

        @JvmInline
        value class BarA(val foo: FooA? = object: FooA("A") {})

        fun main() {
            val matches = BarA().foo?.string == "A"
            // The executable has no stdlib, so use division to expose a bad value.
            val divisor = if (matches) 1 else 0
            val probe = 1 / divisor
        }
        """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("value-class-anonymous-default.kt")
        let output = directory.appendingPathComponent("value-class-anonymous-default")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "ValueClassAnonymousObjectDefaultArgument",
            inputs: [input.path],
            outputPath: output.path,
            emit: .executable,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let execution = try CommandRunner.run(
            executable: output.path,
            arguments: [],
            timeout: 10
        )
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout.isEmpty)
        #expect(execution.stderr.isEmpty)
    }
}
#endif

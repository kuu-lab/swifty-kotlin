#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ValueClassSecondaryConstructorExecutionTests {
    @Test
    func secondaryConstructorsReturnTheirDelegatedUnderlyingValue() throws {
        let source = """
        var calls = 0

        @JvmInline value class V(val x: Int) {
            constructor(s: String) : this(s.length) { calls += 1 }
        }

        @JvmInline value class IC private constructor(val i: Int) {
            constructor() : this(0) {}
        }

        @JvmInline value class W(val x: Int) {
            constructor(a: Int, b: Int) : this(a + b)
            constructor(a: Long, b: Int) : this(a.toInt(), b)
        }

        fun main() {
            // W exercises secondaries with more than one parameter, both
            // called directly and through secondary-to-secondary delegation.
            val matches = V("abc").x == 3 && calls == 1 && IC().i == 0 &&
                W(1, 2).x == 3 && W(2L, 3).x == 5
            // Divide by zero only when a value or constructor side effect is wrong.
            val divisor = if (matches) 1 else 0
            val probe = 1 / divisor
        }
        """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("value-class-secondary-constructor.kt")
        let output = directory.appendingPathComponent("value-class-secondary-constructor")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "ValueClassSecondaryConstructorExecution",
            inputs: [input.path],
            outputPath: output.path,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
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

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct GenericValueClassTypeParameterCastTests {
    /// KUU-3620: the cast inside a generic value-class method must return without recursion.
    @Test(arguments: [0, 2])
    func genericValueClassTypeParameterCastReturnsNormally(optimization: Int) throws {
        let source = """
        annotation class JvmInline

        @JvmInline
        value class R<T>(val a: Any?) {
            fun typed(): T = a as T
        }

        // Preserve the original println call shape without compiling the full stdlib in this test.
        fun println(value: Boolean) {
            if (!value) {
                val invalid: Any? = null
                invalid!!
            }
        }

        fun main() {
            val r = R<Int>(19)
            println(r.typed() == 19)
        }
        """

        try withTemporaryFile(contents: source) { input in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let options = CompilerOptions(
                moduleName: "KUU3620GenericValueClassTypeParameterCast",
                inputs: [input],
                outputPath: output,
                emit: .executable,
                target: TargetTriple.hostDefault(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

            let execution = try CommandRunner.run(executable: output, arguments: [], timeout: 10)
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout.isEmpty)
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendTypeParameterNullCastTests {
    /// KUU-3349: The cast failure must cross the generic call and be catchable.
    @Test
    func definitelyNotNullArgumentMakesGenericNullCastThrow() throws {
        let source = """
        interface Param<T : Any> { val isNullable: Boolean }
        object IntParam : Param<Int> { override val isNullable get() = true }
        fun <T> queryParam(param: Param<T & Any>): T {
            if (param.isNullable) return null as T
            return null as T
        }
        fun main() {
            try {
                queryParam(IntParam)
            } catch (e: Throwable) {
                return
            }
            throw null as Throwable
        }
        """

        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let options = CompilerOptions(
                moduleName: "DefinitelyNotNullGenericNullCast",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            let compilation = makeTestDriver().runForTesting(options: options)
            try assertCompilationSucceeded(compilation)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0)
        }
    }
}
#endif

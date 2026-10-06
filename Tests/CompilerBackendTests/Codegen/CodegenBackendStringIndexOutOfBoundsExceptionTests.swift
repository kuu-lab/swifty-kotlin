@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing
import TestStdlibCache

@Suite
struct CodegenBackendStringIndexOutOfBoundsExceptionTests {
    /// KUU-1069: default imports must expose the runtime's concrete string bounds type.
    @Test(arguments: [false, true])
    func testCatchConstructionThrowAndErasedTypeChecks(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let source = """
        fun main() {
            println(try { "abc"[5] } catch (e: StringIndexOutOfBoundsException) { "SIOOBE" })
            println(StringIndexOutOfBoundsException("x"))
            val e = try { "abc"[5]; null } catch (x: IndexOutOfBoundsException) { x }
            println(e is StringIndexOutOfBoundsException)

            val erased: Any = StringIndexOutOfBoundsException("typed")
            println(erased is StringIndexOutOfBoundsException)
            println(erased is IndexOutOfBoundsException)
            println(erased is ArrayIndexOutOfBoundsException)
            val sibling: Any = ArrayIndexOutOfBoundsException("array")
            println(sibling is StringIndexOutOfBoundsException)

            try {
                throw StringIndexOutOfBoundsException("thrown")
            } catch (e: StringIndexOutOfBoundsException) {
                println(e.message)
            }
        }
        """
        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [inputPath],
                moduleName: "StringIndexOutOfBoundsExceptionRegression",
                emit: .executable,
                outputPath: outputPath,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            SIOOBE
            java.lang.StringIndexOutOfBoundsException: x
            true
            true
            true
            false
            false
            thrown
            """ + "\n")
        }
    }
}

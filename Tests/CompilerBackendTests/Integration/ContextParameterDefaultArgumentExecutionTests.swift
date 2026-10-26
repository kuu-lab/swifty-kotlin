#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ContextParameterDefaultArgumentExecutionTests {
    @Test
    func importedContextParameterStaysAlignedWithDefaultArguments() throws {
        try withCompiledLibrary(
            source: """
            package contextdefaults
            import kotlin.ExperimentalContextParameters

            @OptIn(ExperimentalContextParameters::class)
            context(s: String)
            fun f(useArg: Boolean, arg: String = "K") = if (useArg) arg else s
            """,
            moduleName: "ContextParameterDefaultArguments"
        ) { libraryPath in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let source = directory.appendingPathComponent("consumer.kt").path
            try """
            import contextdefaults.f
            import kotlin.ExperimentalContextParameters

            @OptIn(ExperimentalContextParameters::class)
            fun main() {
                println(with("O") { f(false) })
                println(with("O") { f(true) })
                println(with("O") { f(false) + f(true) })
            }
            """.write(toFile: source, atomically: true, encoding: .utf8)

            let output = directory.appendingPathComponent("consumer").path
            let context = makeCompilationContext(
                inputs: [source], emit: .executable, outputPath: output, searchPaths: [libraryPath]
            )
            try runToLowering(context)
            #expect(!context.diagnostics.hasError, "unexpected diagnostics: \(context.diagnostics.diagnostics)")
            try CodegenPhase().run(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "execution stderr: \(result.stderr)")
            #expect(result.stdout == "O\nK\nOK\n")
        }
    }
}
#endif

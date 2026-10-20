#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ImportedDefaultArgumentInheritanceTests {
    /// An override that omits its base's default arguments keeps them through
    /// a .kklib round-trip: the consumer resolves `Bang().format(7)` against
    /// `Bang.format` and routes the omitted argument through the emitted
    /// `Formatter.format$default` stub. Regression coverage for the
    /// `kotlinx.io.Sink.write` / `Buffer.write` shape, where an imported
    /// override is excluded from the consumer's defaults-inheritance scan.
    @Test func overrideWithoutDefaultsResolvesBaseStubViaLibrary() throws {
        try withCompiledLibrary(
            source: """
            package inheriteddefaults
            interface Formatter {
                fun format(value: Int, suffix: String = "!"): String
            }
            class Bang : Formatter {
                override fun format(value: Int, suffix: String): String = "$value$suffix"
            }
            """,
            moduleName: "InheritedDefaultsLib"
        ) { libraryPath in
            try withTemporaryFile(contents: """
            import inheriteddefaults.Bang
            fun main() {
                println(Bang().format(7))
                println(Bang().format(8, "?"))
            }
            """) { path in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = makeCompilationContext(
                    inputs: [path], emit: .executable, outputPath: output, searchPaths: [libraryPath]
                )
                try runToLowering(context)
                #expect(!context.diagnostics.hasError, "unexpected diagnostics: \(context.diagnostics.diagnostics)")
                try CodegenPhase().run(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "7!\n8?\n")
            }
        }
    }
}
#endif

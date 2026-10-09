@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

struct ImportedVirtualStringABIRegressionTests {
    @Test
    func importedInterfaceDefaultsPreserveNullableStringAndVarargABI() throws {
        try withCompiledLibrary(
            source: """
            package virtualstrings
            interface Renderer {
                fun format(message: String?, value: Any?): String = "$message/$value"
                fun count(vararg values: String): Int = values.size
            }
            object DefaultRenderer : Renderer
            """,
            moduleName: "ImportedVirtualStrings"
        ) { libraryPath in
            try withTemporaryFile(contents: """
            import virtualstrings.Renderer
            import virtualstrings.DefaultRenderer
            fun main() {
                val renderer: Renderer = DefaultRenderer
                println(renderer.format(null, "value"))
                println(renderer.format("prefix", 42))
                println(renderer.count())
                println(renderer.count("one", "two"))
            }
            """) { path in
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = makeCompilationContext(
                    inputs: [path], emit: .executable,
                    outputPath: output, searchPaths: [libraryPath]
                )
                try runToLowering(context)
                try CodegenPhase().run(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "null/value\nprefix/42\n0\n2\n")
            }
        }
    }
}

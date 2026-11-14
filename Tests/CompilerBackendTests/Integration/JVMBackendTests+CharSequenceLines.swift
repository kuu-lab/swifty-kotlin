#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func charSequenceLinesMatchesPrecompiledKotlinConsumer() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = #"""
            fun render(value: CharSequence): String {
                val lines = value.lines()
                return lines.size.toString() + ":" + lines.joinToString("|")
            }
            fun main() {
                println(render(StringBuilder("a\r\nb\nc\rd\n")))
                println(render(""))
                println(render("\r\n\n"))
                println("hello".lines().single())
            }
            """#
            let input = root.appendingPathComponent("Lines.kt")
            try source.write(to: input, atomically: true, encoding: .utf8)
            let reference = root.appendingPathComponent("reference.jar")
            let referenceBuild = try jvmTool("kotlinc", [input.path, "-d", reference.path], root: root)
            try #require(referenceBuild.exitCode == 0, "\(referenceBuild.stderr)")
            let (candidate, exit, diagnostics) = try m22Build(root: root, sources: [("Lines.kt", source)],
                                                            name: "candidate.jar", classpath: [stdlib.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            for program in [reference, candidate] {
                let run = try java(["-cp", program.path + ":" + stdlib.path, "LinesKt"])
                #expect(run.exitCode == 0, "\(run.stderr)")
                #expect(run.stdout == "5:a|b|c|d|\n1:\n3:||\nhello\n")
            }
        }
    }
}
#endif

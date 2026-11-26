#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func prependIndentAndReplaceIndentByMarginMatchKotlinJvm() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = #"""
            fun main() {
                val text = "Hello\nWorld"
                val margin = "\n    |Hello\n    |World\n"
                println(text.prependIndent().replace(" ", "_"))
                println(text.prependIndent("  ").replace(" ", "_"))
                println(text.prependIndent(">>"))
                println("a\n\nb".prependIndent("  ").replace(" ", "_"))
                println("a\n  \nb".prependIndent(" ").replace(" ", "_"))
                println(margin.replaceIndentByMargin("> ", "|"))
                println(margin.replaceIndentByMargin().replace("\n", "/"))
                println("  >left\n    >right".replaceIndentByMargin(marginPrefix = ">").replace("\n", "/"))
            }
            """#
            try source.write(to: root.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)

            let candidate = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: "candidate.jar",
                classpath: [library.path]
            )
            try #require(candidate.1 == 0, "\(candidate.2.map(\.message))")
            #expect(!candidate.2.map(\.message).joined(separator: "\n").contains("Unresolved member function"))

            let runtime = try m11Runtime()
            let candidateRun = try java(["-cp", candidate.0.path + ":" + library.path, "MainKt"])
            _ = try jvmTool("kotlinc", ["-cp", runtime, "Main.kt", "-d", "reference.jar"], root: root)
            let referenceRun = try java([
                "-cp",
                root.appendingPathComponent("reference.jar").path + ":" + runtime,
                "MainKt",
            ])
            #expect(candidateRun.stdout == referenceRun.stdout)
            #expect(candidateRun.stdout.hasPrefix("____Hello\n____World\n__Hello\n__World\n>>Hello\n>>World\n"))
            #expect(candidateRun.stderr.isEmpty)
            #expect(referenceRun.stderr.isEmpty)
        }
    }
}
#endif

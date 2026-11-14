#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedGenericExtensionsResolveThroughTheirMultifileFacade() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let header = "@file:JvmName(\"Queries\")\n@file:JvmMultifileClass\npackage api\n"
            let first = header + "fun <T> List<T>.itemAt(index: Int = 0): T = this[index]\n"
            let second = header + """
            fun <T, R> T.project(transform: (T) -> R): R = transform(this)
            fun <T, R> T.projectSuspending(transform: suspend (T) -> R): suspend () -> R =
                { transform(this) }
            """
            try first.write(to: root.appendingPathComponent("First.kt"), atomically: true, encoding: .utf8)
            try second.write(to: root.appendingPathComponent("Second.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["First.kt", "Second.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import api.itemAt
            import api.project
            import api.projectSuspending
            suspend fun main() {
                println(listOf("first", "second").itemAt())
                println(listOf(2, 5).itemAt(1).project { it * 3 })
                val transform = 3.projectSuspending { it + 5 }
                println(transform())
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "first\n15\n8\n")
            let bytecode = try jvmTool("javap", ["-c", "-classpath", app.path, "MainKt"], root: root)
            #expect(bytecode.stdout.contains("api/Queries.itemAt$default:"))
            #expect(bytecode.stdout.contains("api/Queries.project:"))
        }
    }
}
#endif

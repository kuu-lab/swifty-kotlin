#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [true, false])
    func lazyKotlinExtensionsResolveBySourceName(useAlias: Bool) throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let compose = try composeJVMFixture(root)
            try """
            package androidx.compose.links
            fun String?.asLink(): String = this ?: "missing"
            fun Int.asLink(): String = "id=$this"
            fun ordinary(value: String): String = value
            """.write(to: root.appendingPathComponent("Links.kt"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("links.jar")
            let compiled = try jvmTool("kotlinc", ["Links.kt", "-d", dependency.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let importLine = useAlias ? "import androidx.compose.links.asLink as link" : "import androidx.compose.links.*"
            let call = useAlias ? "link" : "asLink"
            let source = """
            \(importLine)
            fun main() {
                val missing: String? = null
                println("host".\(call)())
                println(missing.\(call)())
                println(7.\(call)())
            }
            """
            let classpath = [compose.path, dependency.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "host\nmissing\nid=7\n")
        }
    }
}
#endif

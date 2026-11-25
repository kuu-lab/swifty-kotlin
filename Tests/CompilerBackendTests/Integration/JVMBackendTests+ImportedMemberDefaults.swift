#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinMembersInvokeDefaultHelpersWithDispatchReceivers() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let dependency = """
            package api
            class Style(val label: String) {
                fun describe(prefix: String = label, count: Int): String = prefix + count
                companion object {
                    @JvmStatic
                    @JvmOverloads
                    fun create(label: String, suffix: String = "!"): Style = Style(label + suffix)
                    fun named(prefix: String = "default", suffix: String): Style = Style(prefix + suffix)
                }
            }
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import api.Style
            fun main() {
                println(Style("plain").describe(count = 3))
                println(Style.create(label = "static").describe(count = 2))
                println(Style.Companion.create("explicit", "?").describe("override", 4))
                println(Style.named(suffix = "!").describe(count = 1))
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "plain3\nstatic!2\noverride4\ndefault!1\n")

            let (_, rejected, errors) = try m22Build(
                root: root,
                sources: [("Missing.kt", "import api.Style\nfun invalid() = Style.named()")],
                name: "missing.jar", classpath: classpath
            )
            #expect(rejected != 0)
            #expect(errors.contains { $0.message.contains("No value passed for parameter 'suffix'") })
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinExtensionDefaultsUseTheClassfileHelper() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let wideParameters = (0...32).map { "p\($0): Int = \($0)" }.joined(separator: ", ")
            let dependency = """
            package api
            fun String.describe(first: String = this, count: Int, last: String? = "!"): String =
                first + count + (last ?: "?")
            fun String.wide(\(wideParameters)): Int = length + p0 + p31 + p32
            class Style private constructor(val name: String) {
                companion object {
                    @JvmStatic fun of(name: String): Style = Style(name)
                }
            }
            fun Style.describe(first: String = name): String = first
            """
            try dependency.write(to: root.appendingPathComponent("Dependency.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("dependency.jar")
            let compiled = try jvmTool("kotlinc", ["Dependency.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let source = """
            import api.Style
            import api.describe
            import api.wide

            fun mark(value: String): String {
                println(value)
                return value
            }
            fun main() {
                println(mark("receiver").describe(last = mark("last"), count = 2))
                println("base".describe(count = 3))
                println("base".describe("explicit", 4, null))
                println("abc".wide(p32 = 4))
                println(Style.of("style").describe())
            }
            """
            let classpath = [library.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "receiver\nlast\nreceiver2last\nbase3!\nexplicit4?\n38\nstyle\n")

            let (_, rejected, errors) = try m22Build(
                root: root,
                sources: [("Missing.kt", "import api.describe\nfun invalid() = \"base\".describe()")],
                name: "missing.jar", classpath: classpath
            )
            #expect(rejected != 0)
            #expect(errors.contains { $0.message.contains("No value passed for parameter 'count'") })
        }
    }
}
#endif

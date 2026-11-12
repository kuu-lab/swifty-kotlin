#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedConstructorDefaultsPreserveGenericInputs() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            class Items(val entries: List<String>, val label: String = "default", val size: Int = entries.size) {
                constructor(label: String): this(listOf("secondary"), label)
                fun summary(): String = "$label:$size"
            }
            fun <T> emptyEntries(): List<T> = emptyList()
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.Items
            import fixture.emptyEntries
            fun main() {
                println(Items(entries = emptyEntries()).summary())
                println(Items(size = 3, entries = listOf("entry")).summary())
                println(Items(listOf("entry"), "given", 4).summary())
                println(Items("secondary").summary())
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "default:0\n"
                + "default:3\n"
                + "given:4\n"
                + "secondary:1\n")
        }
    }
}
#endif

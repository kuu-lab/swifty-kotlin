#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedConstructorsKeepKotlinParameterTypes() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture

            interface Qualifier
            class Item(val qualifiers: Set<Qualifier>, val path: String, vararg val tags: String)
            class Box<T>(val values: List<T>, val fallback: T?)
            """.write(to: root.appendingPathComponent("Item.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("item.jar")
            let compiled = try jvmTool("kotlinc", ["Item.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import fixture.Box
            import fixture.Item

            fun main() {
                val item = Item(setOf(), "path", "a", "b")
                val box = Box(listOf(1, 2), null)
                println(item.path + item.qualifiers.size + item.tags.size + box.values.size)
            }
            """
            let classpath = [library.path, own.path]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "path022\n", "\(run.stderr)")
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedKotlinOperatorIteratorKeepsSingleModifier() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture

            class Bag<T>(private val items: List<T>) : Iterable<T> {
                override operator fun iterator(): Iterator<T> = items.iterator()
            }

            class MutableBag<T>(private val items: MutableList<T>) : MutableIterable<T> {
                override operator fun iterator(): MutableIterator<T> = items.iterator()
            }

            fun makeBag(): Bag<String> = Bag(listOf("a", "b"))
            fun makeMutableBag(): MutableBag<String> = MutableBag(mutableListOf("c"))
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.makeBag
            import fixture.makeMutableBag
            fun main() {
                for (item in makeBag()) println(item)
                for (item in makeMutableBag()) println(item)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "a\nb\nc\n")
        }
    }
}
#endif

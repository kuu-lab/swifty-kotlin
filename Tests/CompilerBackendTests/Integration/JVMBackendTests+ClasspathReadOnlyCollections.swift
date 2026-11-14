#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedReadOnlyListKeepsCovariantSubListAndPersistentMethods() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            interface ImmutableList<E> : List<E> {
                override fun subList(fromIndex: Int, toIndex: Int): ImmutableList<E>
            }
            interface PersistentList<E> : ImmutableList<E> {
                fun add(item: E): PersistentList<E>
                fun clear(): PersistentList<E>
            }
            private class Persistent<E>(private val elements: List<E>) : PersistentList<E>, List<E> by elements {
                override fun subList(fromIndex: Int, toIndex: Int): ImmutableList<E> =
                    Persistent(elements.subList(fromIndex, toIndex))
                override fun add(item: E): PersistentList<E> = Persistent(elements + item)
                override fun clear(): PersistentList<E> = Persistent(emptyList())
            }
            fun items(): PersistentList<String> = Persistent(listOf("DroidKaigi", "next"))
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.items
            fun main() {
                val items = items()
                val list: List<String> = items.subList(0, 1)
                println(list.first())
                val appended = items.add("third") as List<*>
                val cleared = items.clear() as List<*>
                println(appended.size)
                println(cleared.size)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "DroidKaigi\n3\n0\n")
        }
    }
}
#endif

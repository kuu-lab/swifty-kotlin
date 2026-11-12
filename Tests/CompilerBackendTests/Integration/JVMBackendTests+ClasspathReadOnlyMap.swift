#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedReadOnlyMapKeepsCovariantViewsAndPersistentMethods() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let provider = """
            package fixture
            interface Keys<E> : Set<E>
            private class KeySet<E>(source: Set<E>) : Keys<E>, Set<E> by source
            interface PersistentMap<K, V> : Map<K, V> {
                override val keys: Keys<K>
                fun clear(): PersistentMap<K, V>
            }
            private class Persistent<K, V>(private val source: Map<K, V>) : PersistentMap<K, V>, Map<K, V> by source {
                override val keys: Keys<K> get() = KeySet(source.keys)
                override fun clear(): PersistentMap<K, V> = Persistent(emptyMap())
            }
            fun entries(): PersistentMap<String, Int> = Persistent(mapOf("DroidKaigi" to 1))
            """
            try provider.write(to: root.appendingPathComponent("Provider.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["Provider.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [library.path, own.path]
            let source = """
            import fixture.entries
            fun main() {
                val entries = entries()
                val keys: Set<String> = entries.keys
                println(keys.first())
                val cleared = entries.clear() as Map<*, *>
                println(cleared.size)
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.stdout == "DroidKaigi\n0\n")
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledMutableListIteratorLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            class Cursor(source: MutableListIterator<Int>) : MutableListIterator<Int> by source
            class Entry(override val key: Int, private var stored: Int) : MutableMap.MutableEntry<Int, Int> {
                override val value: Int get() = stored
                override fun setValue(newValue: Int): Int {
                    val previous = stored
                    stored = newValue
                    return previous
                }
            }
            fun main() {
                val numbers = java.util.ArrayList<Int>()
                numbers.add(10)
                val cursor = Cursor(numbers.listIterator())
                println(cursor.next())
                cursor.set(20)
                println(numbers[0])
                println(Entry(1, 3).setValue(4))
                println(Cursor::class.java.interfaces.map { it.name }.sorted().joinToString())
                println(Entry::class.java.interfaces.map { it.name }.sorted().joinToString())
                // Marker inheritance: KMutableList/KMutableSet <: KMutableCollection <: KMutableIterable.
                println(kotlin.jvm.internal.markers.KMutableList::class.java.interfaces.map { it.simpleName }.sorted().joinToString())
                println(kotlin.jvm.internal.markers.KMutableSet::class.java.interfaces.map { it.simpleName }.sorted().joinToString())
                println(kotlin.jvm.internal.markers.KMutableCollection::class.java.interfaces.map { it.simpleName }.sorted().joinToString())
            }
            """
            try source.write(to: root.appendingPathComponent("MarkerProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["MarkerProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let args = ["-Xverify:all", "-cp"]
            let reference = try java(args + [app.path + ":" + (try m11Runtime()), "MarkerProbeKt"])
            let run = try java(args + [app.path + ":" + stdlib.path, "MarkerProbeKt"])
            #expect(run.stdout == reference.stdout)
            #expect(run.stdout.contains("kotlin.jvm.internal.markers.KMutableListIterator"))
            #expect(run.stdout.contains("kotlin.jvm.internal.markers.KMutableMap$Entry"))
        }
    }
}
#endif

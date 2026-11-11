#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func abstractListSupportsPrecompiledKotlinSubclasses() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                private class Items(private val elements: List<String?>) : AbstractList<String?>() {
                    override val size: Int get() = elements.size
                    override fun get(index: Int): String? = elements[index]
                }

                fun main() {
                    val elements = listOf("a", null, "a", "b")
                    val items = Items(elements)
                    val list: List<String?> = items
                    println(list.size)
                    println(list == elements)
                    println(list.hashCode() == elements.hashCode())
                    println(list.indexOf(null))
                    println(list.lastIndexOf("a"))
                    println(list.subList(1, 3))
                    val cursor = items.listIterator(2)
                    println(cursor.next())
                    println(cursor.previous())
                    println(cursor.previous())
                    val erased: Any = list
                    println(erased is MutableList<*>)
                    val array = arrayOf("a", null, "a")
                    println(array.indexOf(null))
                    println(array.lastIndexOf("a"))
                    println(array.indexOf("missing"))
                }
                """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            _ = try jvmTool("kotlinc", ["Main.kt", "-d", "precompiled.jar"], root: root)
            let expected = "4\ntrue\ntrue\n1\n2\n[null, a]\na\na\nnull\nfalse\n1\n2\n-1\n"
            for consumer in [app, root.appendingPathComponent("precompiled.jar")] {
                let run = try java(["-Xverify:all", "-cp", consumer.path + ":" + stdlib.path, "MainKt"])
                #expect(run.stdout == expected)
                #expect(run.stderr.isEmpty)
            }
        }
    }
}
#endif

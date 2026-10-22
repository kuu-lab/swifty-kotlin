#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionOperatorsPreserveCopiesAndOfficialRuntimeABI(mode: EmitMode) throws {
        let source = """
        class Parser<T>
        fun mutation(map: Map<String, Int>) {
            try {
                val changed = map as MutableMap<String, Int>
                changed["z"] = 9
                println("mutable")
            } catch (e: ClassCastException) { println("cast") }
              catch (e: UnsupportedOperationException) { println("immutable") }
        }
        fun main() {
            val list = listOf(1, 2, 2, 3)
            println(list + 4); println(list.plus(4))
            println(list + listOf(4, 5)); println(list.plus(listOf(4, 5)))
            println(list - 2); println(list.minus(2))
            println(list - setOf(1, 3)); println(list.minus(listOf(1, 3)))
            println(list)
            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
            println(map - "b"); println(map.minus("missing"))
            println(map - setOf("a", "c"))
            println(map + ("b" to 7)); println(map.plus(mapOf("d" to 4)))
            println(map)
            val nullable = mapOf<String?, Int?>(null to null, "a" to 1)
            println(nullable - "a"); println(nullable + ("b" to null))
            val nullableList = listOf<Int?>(null, 1, null)
            println(nullableList - null); println(nullableList - listOf(null))
            val values: List<Any?> = emptyList()
            println((values + Parser<Boolean>()).size)
            mutation(mapOf("a" to 1) - "a")
            mutation(mapOf("a" to 1, "b" to 2) - "a")
            mutation(emptyMap<String, Int>() + ("a" to 1))
            mutation(emptyMap<String, Int>() + mapOf("a" to 1))
        }
        """
        let expected = "[1, 2, 2, 3, 4]\n[1, 2, 2, 3, 4]\n[1, 2, 2, 3, 4, 5]\n[1, 2, 2, 3, 4, 5]\n[1, 2, 3]\n[1, 2, 3]\n[2, 2]\n[2, 2]\n[1, 2, 2, 3]\n{a=1, c=3}\n{a=1, b=2, c=3}\n{b=2}\n{a=1, b=7, c=3}\n{a=1, b=2, c=3, d=4}\n{a=1, b=2, c=3}\n{null=null}\n{null=null, a=1, b=null}\n[1, null]\n[1]\n1\ncast\nimmutable\nimmutable\nmutable\n"
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-d", "official.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("official.jar").path + ":" + library.path, "HelloKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif

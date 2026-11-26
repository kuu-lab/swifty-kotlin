#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableMapPutIfAbsentMatchesKotlinJVM(mode: EmitMode) throws {
        let library = try ownStdlibRuntime()
        try withWorkspace { root in
            let source = """
            class DelegatingMap(private val backing: MutableMap<String, String>) : MutableMap<String, String> by backing {
                override fun get(key: String): String? {
                    println("get override")
                    return backing.get(key)
                }
                override fun put(key: String, value: String): String? {
                    println("put override")
                    return backing.put(key, value)
                }
            }
            open class BaseMap : MutableMap<String, String> by mutableMapOf()
            class ChildMap : BaseMap() {
                fun addMissing() = super.putIfAbsent("super", "inserted")
            }

            fun main() {
                val values = linkedMapOf<String, String?>("null" to null, "present" to "old")
                println(values.putIfAbsent("new", "first"))
                println(values.putIfAbsent("present", "replacement"))
                println(values.putIfAbsent("null", "filled"))
                println(values.entries.joinToString(",") { "${it.key}=${it.value}" })

                val typed: MutableMap<String, String?> = linkedMapOf("present" to "old")
                println(typed.putIfAbsent("present", "replacement"))
                println(typed.putIfAbsent("new", "first"))

                val delegated = DelegatingMap(mutableMapOf())
                println(delegated.putIfAbsent("key", "first"))
                println(delegated.putIfAbsent("key", "replacement"))

                println(ChildMap().addMissing())

                val referenceMap: MutableMap<String, String> = linkedMapOf()
                val reference: (String, String) -> String? = referenceMap::putIfAbsent
                println(reference("reference", "first"))
                println(reference("reference", "replacement"))
                val unitReference: (String, String) -> Unit = referenceMap::putIfAbsent
                unitReference("unit", "inserted")
                println(referenceMap.get("unit"))
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            let expected = """
            null
            old
            null
            null=filled,present=old,new=first
            old
            null
            get override
            put override
            null
            get override
            first
            null
            null
            first
            inserted
            """ + "\n"
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)

            let referenceCompile = try jvmTool("kotlinc", ["hello.kt", "-d", "reference.jar"], root: root)
            try #require(referenceCompile.exitCode == 0, "\(referenceCompile.stderr)")
            let runtime = try m11Runtime()
            let referenceExecution = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(referenceExecution.stdout == expected)
            #expect(referenceExecution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableMapPutIfAbsentCallableReflectionExposesJavaParameters(mode: EmitMode) throws {
        let library = try ownStdlibRuntime()
        try withWorkspace { root in
            let result = try compile("""
            fun main() {
                val map = linkedMapOf<String, String>()
                val reference = map::putIfAbsent
                println(reference.parameters.size)
                println(reference.callBy(mapOf(reference.parameters[0] to "key", reference.parameters[1] to "first")))
                println(reference.callBy(mapOf(reference.parameters[0] to "key", reference.parameters[1] to "replacement")))
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "2\nnull\nfirst\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableMapPutIfAbsentRejectsReadOnlyMap(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            fun main() {
                val values: Map<String, String> = mapOf("a" to "b")
                values.putIfAbsent("c", "d")
            }
            """, root: root, mode: mode)
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0024" })
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif

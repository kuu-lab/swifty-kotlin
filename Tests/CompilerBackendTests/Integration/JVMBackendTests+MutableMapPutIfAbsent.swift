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
            fun main() {
                val values = linkedMapOf<String, String?>("null" to null, "present" to "old")
                println(values.putIfAbsent("new", "first"))
                println(values.putIfAbsent("present", "replacement"))
                println(values.putIfAbsent("null", "filled"))
                println(values.entries.joinToString(",") { "${it.key}=${it.value}" })

                val typed: MutableMap<String, String?> = linkedMapOf("present" to "old")
                println(typed.putIfAbsent("present", "replacement"))
                println(typed.putIfAbsent("new", "first"))
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

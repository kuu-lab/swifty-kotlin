#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapHigherOrderFunctionsUseBundledStdlib(mode: EmitMode) throws {
        let source = """
        fun main() {
            val values = mapOf("a" to 1)
            println(values.getOrElse("missing") { println("missing-default"); 0 })
            println(values.getOrElse("a") { println("unused-getOrElse"); -1 })

            val mutable = mutableMapOf<String, Int>()
            println(mutable.getOrPut("a") { println("insert-default"); 5 })
            println(mutable.getOrPut("a") { println("unused-getOrPut"); 6 })
            println(mutable)

            println(values.mapKeys { it.key.uppercase() })
            println(values.mapValues { it.value * 10 })
            println(values.filterKeys { it == "a" })
            println(values.filterValues { it > 0 })
        }
        """
        let expected = "missing-default\n0\n1\ninsert-default\n5\n5\n{a=5}\n{A=1}\n{a=10}\n{a=1}\n{a=1}\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "map-operations.jar" : "map-operations-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool(
                "kotlinc",
                ["-cp", runtime, "Main.kt", "-d", "consumer.jar"],
                root: root
            )
            let consumer = try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + runtime, "MainKt"])
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }
}
#endif

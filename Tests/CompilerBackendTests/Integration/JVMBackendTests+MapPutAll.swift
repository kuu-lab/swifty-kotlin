#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableMapPutAllCopiesMappedValues(mode: EmitMode) throws {
        let source = """
        fun submitInteraction(actionContext: Map<String, Any>? = null) {
            val actionContextFinal = mutableMapOf<String, String>()
            actionContextFinal["source"] = "test"
            actionContext?.let {
                actionContextFinal.putAll(it.mapValues { (_, value) -> value.toString() })
            }
            println(actionContextFinal)
        }

        fun main() {
            submitInteraction(mapOf("source" to "override", "count" to 2, "label" to "x"))
            submitInteraction()
        }
        """
        let expected = "{source=override, count=2, label=x}\n{source=test}\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: mode == .jvmJar ? "map-putall.jar" : "map-putall-classes",
                mode: mode,
                classpath: runtime.components(separatedBy: ":")
            )
            try #require(app.1 == 0, "KSwiftK diagnostics: \(app.2.map { "\($0.code) @\($0.primaryRange?.start.offset ?? -1): \($0.message)" })")

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

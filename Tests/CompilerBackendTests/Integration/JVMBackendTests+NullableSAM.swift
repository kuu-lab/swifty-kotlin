#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func nullableSAMConversionsPreserveNullAndEvaluateOnce(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            fun interface Action { fun run() }
            var reads = 0
            var calls = 0
            fun create(present: Boolean): (() -> Unit)? {
                reads++
                return if (present) ({ calls++ }) else null
            }
            fun accept(action: Action?): Boolean { action?.run(); return action == null }
            fun main() {
                println(accept(create(false)))
                println(accept(create(true)))
                val absent: (() -> Unit)? = null
                val present: (() -> Unit)? = { calls += 2 }
                val direct: () -> Unit = { calls += 4 }
                println(accept(absent))
                println(accept(present))
                println(accept(direct))
                println(accept(null))
                println(accept { calls += 8 })
                println(reads)
                println(calls)
            }
            """, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", artifact.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "true\nfalse\ntrue\nfalse\nfalse\ntrue\nfalse\n2\n15\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func genericArraySortByCompilesAndRuns(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            fun main() {
                val values: Array<out Int> = arrayOf(1, 2)
                values.sortBy { -it }
                println(values.toList())
                println(arrayOf(2, 1).sortedByDescending { it })
                println(arrayOf("a", "bb", "c").sortedByDescending { if (it.length == 1) null else it.length })
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map { "\($0.code) @\($0.primaryRange?.start.offset ?? -1): \($0.message)" })")
            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "[2, 1]\n[2, 1]\n[bb, a, c]\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

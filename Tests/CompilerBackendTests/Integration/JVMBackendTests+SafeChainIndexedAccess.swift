#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func safeChainIndexedAccessSkipsIndexOnNullReceiver(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            var indexEvaluations = 0

            fun index(): Int {
                indexEvaluations += 1
                return 0
            }

            class Box {
                operator fun get(index: Int): Int = 40 + index
            }
            class Source(val box: Box)

            fun main() {
                val missing: Source? = null
                val nullResult = missing?.box[index()]
                println(nullResult == null)
                println(indexEvaluations)

                val present = Source(Box())
                println(present?.box[index()])
                println(indexEvaluations)
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "true\n0\n40\n1\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

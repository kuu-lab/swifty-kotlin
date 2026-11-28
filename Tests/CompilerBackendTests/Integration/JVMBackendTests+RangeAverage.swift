#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func rangeAverageResolvesAgainstOfficialStdlib() throws {
        let runtime = try m11Runtime()
        let classpath = runtime.components(separatedBy: ":")
        try withWorkspace { root in
            let source = """
            fun main() {
                val range = 1..10
                println(range.take(3))
                println(range.drop(7))
                println((1..5).average())
                println((5 downTo 1).average())
                println((5..1).average())
                println((1..5).sorted())
            }
            """
            let compilation = try compile(
                source,
                root: root,
                mode: .jvmJar,
                classpath: classpath
            )
            try #require(compilation.0 == 0, "\(compilation.1.map(\.message))")

            let artifact = root.appendingPathComponent("hello.jar").path
            let execution = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "[1, 2, 3]\n[8, 9, 10]\n3.0\n3.0\nNaN\n[1, 2, 3, 4, 5]\n")
            #expect(execution.stderr.isEmpty)

            let referenceCompile = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            try #require(referenceCompile.exitCode == 0, "\(referenceCompile.stderr)")
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == reference.stdout)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif

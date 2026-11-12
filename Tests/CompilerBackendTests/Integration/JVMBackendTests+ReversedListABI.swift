#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledReadOnlyAsReversedUsesALiveView() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val backing = mutableListOf(1, 2)
                val source: List<Int> = backing
                val reversed = source.asReversed()
                println(reversed.joinToString())
                backing.add(3)
                println(reversed.joinToString())
                println(reversed[1])
                try {
                    println(reversed[3])
                } catch (_: IndexOutOfBoundsException) {
                    println("outside")
                }
            }
            """
            try source.write(to: root.appendingPathComponent("Reverse.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Reverse.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "ReverseKt"])
            #expect(run.stdout == "2, 1\n3, 2, 1\n2\noutside\n")
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledListBinarySearchUsesOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val list = listOf(null, 2, 4, 6)
                println(list.binarySearch(null))
                println(list.binarySearch(4))
                println(list.binarySearch(3))
                println(list.binarySearch(2, fromIndex = 2))
                println(list.binarySearch(6, toIndex = 3))
                println(emptyList<Int>().binarySearch(1))
                try { list.binarySearch(4, 3, 1) }
                catch (_: IllegalArgumentException) { println("reversed") }
                try { list.binarySearch(4, -1) }
                catch (_: IndexOutOfBoundsException) { println("negative") }
            }
            """
            try source.write(to: root.appendingPathComponent("Probe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Probe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let official = try java(["-cp", app.path + ":" + m11Runtime(), "ProbeKt"])
            let candidate = try java(["-cp", app.path + ":" + stdlib.path, "ProbeKt"])
            #expect(candidate.stdout == "0\n2\n-3\n-3\n-4\n-1\nreversed\nnegative\n")
            #expect(candidate.stdout == official.stdout)
        }
    }
}
#endif

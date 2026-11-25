#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledMutableListSortUsesOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val empty = mutableListOf<String>()
                val single = mutableListOf("one")
                val values = mutableListOf("b", "c", "a", "b")
                empty.sort()
                single.sort()
                values.sort()
                println(empty)
                println(single)
                println(values)
            }
            """
            try source.write(to: root.appendingPathComponent("Probe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Probe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let official = try java(["-cp", app.path + ":" + m11Runtime(), "ProbeKt"])
            let candidate = try java(["-cp", app.path + ":" + stdlib.path, "ProbeKt"])
            #expect(candidate.stdout == "[]\n[one]\n[a, b, b, c]\n")
            #expect(candidate.stdout == official.stdout)
        }
    }
}
#endif

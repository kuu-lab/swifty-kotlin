#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledMutableListReverseUsesOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val empty = mutableListOf<String>()
                val single = mutableListOf("one")
                val odd = mutableListOf("one", "two", "three")
                val even = mutableListOf("one", null, "three", "four")
                empty.reverse()
                single.reverse()
                odd.reverse()
                even.reverse()
                println(empty)
                println(single)
                println(odd)
                println(even)
            }
            """
            try source.write(to: root.appendingPathComponent("Probe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Probe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let official = try java(["-cp", app.path + ":" + m11Runtime(), "ProbeKt"])
            let candidate = try java(["-cp", app.path + ":" + stdlib.path, "ProbeKt"])
            #expect(candidate.stdout == "[]\n[one]\n[three, two, one]\n[four, three, null, one]\n")
            #expect(candidate.stdout == official.stdout)
        }
    }
}
#endif

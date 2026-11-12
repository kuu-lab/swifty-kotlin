#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledJoinToUsesOwnStdlibAndRetainsTheBuffer() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val buffer = StringBuilder("before ")
                val joined = listOf(1, 2, 3).joinTo(buffer, prefix = "[", postfix = "]", limit = 1) { "n" + it }
                println(joined === buffer)
                println(joined)
                println(listOf(null, 'x').joinTo(StringBuilder()))
                println(emptyList<Int>().joinTo(StringBuilder(), prefix = "<", postfix = ">"))
            }
            """
            try source.write(to: root.appendingPathComponent("JoinToProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["JoinToProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "JoinToProbeKt"])
            #expect(run.stdout == "true\nbefore [n1, ...]\nnull, x\n<>\n")
        }
    }
}
#endif

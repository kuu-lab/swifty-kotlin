#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledArrayLastIndexLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                println(longArrayOf(4L, 5L).lastIndex)
                println(longArrayOf().lastIndex)
                println(floatArrayOf(1f, 2f, 3f).lastIndex)
                println(floatArrayOf().lastIndex)
            }
            """
            try source.write(to: root.appendingPathComponent("Indices.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Indices.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "IndicesKt"])
            #expect(run.stdout == "1\n-1\n2\n-1\n")
        }
    }
}
#endif

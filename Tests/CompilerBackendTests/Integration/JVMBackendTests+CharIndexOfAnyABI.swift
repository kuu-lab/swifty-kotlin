#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledCharIndexOfAnyLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val value: CharSequence = "https://test"
                println(value.indexOfAny(charArrayOf('/', ':')))
                println(value.indexOfAny(charArrayOf('/'), startIndex = 7))
                println(value.indexOfAny(charArrayOf('H'), startIndex = -2, ignoreCase = true))
                println(value.indexOfAny(charArrayOf('H')))
                println(value.indexOfAny(charArrayOf(), startIndex = value.length))
            }
            """
            try source.write(to: root.appendingPathComponent("IndexOfAny.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["IndexOfAny.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "IndexOfAnyKt"])
            #expect(run.stdout == "5\n7\n0\n-1\n-1\n")
        }
    }
}
#endif

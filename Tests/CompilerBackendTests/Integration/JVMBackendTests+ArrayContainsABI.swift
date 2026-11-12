#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledArrayContainsLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            data class Entry(val key: Int)
            fun main() {
                val entries = arrayOf(Entry(1), null, Entry(2))
                println(Entry(2) in entries)
                println(Entry(3) in entries)
                println(null in entries)
                println(null in emptyArray<Entry?>())
            }
            """
            try source.write(to: root.appendingPathComponent("ArrayProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["ArrayProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "ArrayProbeKt"])
            #expect(run.stdout == "true\nfalse\ntrue\nfalse\n")
        }
    }
}
#endif

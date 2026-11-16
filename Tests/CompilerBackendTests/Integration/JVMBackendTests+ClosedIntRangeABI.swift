#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledIntRangeCoercionUsesOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val range: ClosedRange<Int> = 2..4
                println(1.coerceIn(range))
                println(3.coerceIn(range))
                println(7.coerceIn(range))
                println(3 in range)
                val open: OpenEndRange<Int> = 2..4
                println(open.endExclusive)
                try {
                    println(7.coerceIn(IntRange.EMPTY))
                } catch (_: IllegalArgumentException) {
                    println("empty")
                }
            }
            """
            try source.write(to: root.appendingPathComponent("IntRangeProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["IntRangeProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "IntRangeProbeKt"])
            #expect(run.stdout == "2\n3\n4\ntrue\n5\nempty\n")
        }
    }
}
#endif

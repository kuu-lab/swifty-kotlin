#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledMonotonicTimeSourceLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import kotlin.time.Duration
            import kotlin.time.TimeSource
            import kotlin.time.Duration.Companion.seconds

            fun main() {
                val mark = TimeSource.Monotonic.markNow()
                val later = mark + 2.seconds
                println(later - mark == 2.seconds)
                println(later > mark)
                println(mark.elapsedNow() >= Duration.ZERO)
                println((mark + Duration.INFINITE).elapsedNow().isNegative())
                val source: TimeSource = TimeSource.Monotonic
                println(source.markNow().hasPassedNow())
            }
            """
            try source.write(to: root.appendingPathComponent("MonotonicProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["MonotonicProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "MonotonicProbeKt"])
            #expect(run.stdout == String(repeating: "true\n", count: 5))
        }
    }
}
#endif

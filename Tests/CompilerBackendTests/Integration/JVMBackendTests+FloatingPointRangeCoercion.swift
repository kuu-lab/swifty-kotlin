#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledFloatingPointRangeCoercionUsesOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val floats = 0.0f..1.0f
                println((-0.5f).coerceIn(floats))
                println(0.5f.coerceIn(floats))
                println(1.5f.coerceIn(floats))
                println(Float.NaN.coerceIn(floats).isNaN())
                println((-0.0f).coerceIn(floats).toRawBits())
                val doubles = -1.0..1.0
                println(2.0.coerceIn(doubles))
                try {
                    println(0.0.coerceIn(1.0..0.0))
                } catch (_: IllegalArgumentException) {
                    println("empty")
                }
            }
            """
            try source.write(to: root.appendingPathComponent("Probe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Probe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let official = try java(["-cp", app.path + ":" + m11Runtime(), "ProbeKt"])
            let candidate = try java(["-cp", app.path + ":" + stdlib.path, "ProbeKt"])
            #expect(candidate.stdout == "0.0\n0.5\n1.0\ntrue\n-2147483648\n1.0\nempty\n")
            #expect(candidate.stdout == official.stdout)
        }
    }
}
#endif

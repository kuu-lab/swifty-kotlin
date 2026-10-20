#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibMathMinMax(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            import kotlin.math.min
            import kotlin.math.max
            fun main() {
                println(min(7, 3))
                println(max(7, 3))
                println(min(-9223372036854775807L, 7L))
                println(max(-9223372036854775807L, 7L))
                println(min(2.5, 1.25))
                println(max(2.5f, 1.25f))
                val minNaN = min((0.0 / 0.0), 1.0)
                val maxNaN = max(1.0, (0.0 / 0.0))
                println(minNaN != minNaN)
                println(maxNaN != maxNaN)
                println(1.0 / min(-0.0, 0.0))
                println(1.0 / max(-0.0, 0.0))
                val floatNaN = min((0.0f / 0.0f), 1.0f)
                println(floatNaN != floatNaN)
                println(1.0f / max(-0.0f, 0.0f))
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "3\n7\n-9223372036854775807\n7\n1.25\n2.5\ntrue\ntrue\n-Infinity\nInfinity\ntrue\nInfinity\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

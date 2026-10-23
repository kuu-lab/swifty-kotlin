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

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibMathSurface(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            import kotlin.math.*
            fun main() {
                println(max(3, 7) + min(3, 7) + abs(-5))
                println(sqrt(16.0))
                println(2.0.pow(10.0))
                println(floor(2.7) + ceil(2.1))
                println(round(2.5))
                println(truncate(2.9))
                println(sign(-3.5))
                println(hypot(3.0, 4.0))
                println(ln(E))
                println(log10(1000.0))
                println(PI)
                println((-4.5).absoluteValue)
                println((-3.5).sign)
                println((-9L).sign)
                println(2.5.roundToInt())
                println((-2.5).roundToLong())
                println(2.0.withSign(-1))
                println(2.0f.pow(3))
                println(sqrt(9.0f))
                println(atan2(1.0, 0.0) > 1.57)
                println(log2(8.0) == 3.0)
                println(expm1(0.0) == 0.0)
                println(ln1p(0.0) == 0.0)
                println(acosh(1.0) == 0.0)
                println(asinh(0.0) == 0.0)
                println(atanh(1.0).isInfinite())
                println(1.0.nextUp() > 1.0)
                println(1.0.nextDown() < 1.0)
                println(1.0.nextTowards(2.0) > 1.0)
                println(7.0.IEEErem(2.5) == -0.5)
                println(1.0.ulp > 0.0)
                println(min(1u, 2u) == 1u)
                println(max(1uL, 2uL) == 2uL)
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == """
            15
            4.0
            1024.0
            5.0
            2.0
            2.0
            -1.0
            5.0
            1.0
            3.0
            3.141592653589793
            4.5
            -1.0
            -1
            3
            -2
            -2.0
            8.0
            3.0
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true

            """)
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

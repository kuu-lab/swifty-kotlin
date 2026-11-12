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

    @Test
    func externalMathCallsUsePublicJVMMethods() throws {
        let runtime = try m11Runtime()
        let classpath = runtime.components(separatedBy: ":")
        try withWorkspace { root in
            let source = """
            import kotlin.math.hypot
            import kotlin.math.ln1p
            import kotlin.math.ulp
            import kotlin.math.withSign
            fun main() {
                println(hypot(3.0, 4.0))
                println(hypot(3.0f, 4.0f))
                println(hypot(Double.POSITIVE_INFINITY, Double.NaN) == Double.POSITIVE_INFINITY)
                println(hypot(Double.NaN, 0.0).isNaN())
                println(1.0 / hypot(-0.0, -0.0))
                println(ln1p(1.0e-20) > 0.0)
                println(1.0 / ln1p(-0.0))
                println(ln1p(-1.0) == Double.NEGATIVE_INFINITY)
                println(ln1p(-2.0).isNaN())
                println(1.0.ulp > 0.0)
                println(0.0.ulp == (-0.0).ulp)
                println(Double.NaN.ulp.isNaN())
                println(1.0f.ulp > 0.0f)
                println(0.0f.ulp == (-0.0f).ulp)
                println(Float.NaN.ulp.isNaN())
                println(2.0.withSign(-1.0))
                println(2.0.withSign(-1))
                println(2.0f.withSign(-1.0f))
                println(2.0f.withSign(-1))
                println(1.0 / (0.0.withSign(-0.0)))
                println(1.0 / ((-0.0).withSign(0.0)))
                println(1.0f / (0.0f.withSign(-0.0f)))
                println((Double.NaN.withSign(-1.0)).isNaN())
            }
            """
            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: classpath)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let artifact = root.appendingPathComponent("hello.jar")
            let candidate = try java(["-cp", artifact.path + ":" + runtime, "HelloKt"])
            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "official.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("official.jar").path + ":" + runtime, "HelloKt"])
            let expected = [
                "5.0", "5.0", "true", "true", "Infinity", "true", "-Infinity", "true", "true",
                "true", "true", "true", "true", "true", "true", "-2.0", "-2.0", "-2.0", "-2.0", "-Infinity", "Infinity", "-Infinity", "true",
            ].joined(separator: "\n") + "\n"
            #expect(candidate.exitCode == 0)
            #expect(candidate.stdout == expected)
            #expect(candidate.stdout == reference.stdout)
            #expect(candidate.stderr.isEmpty)
            #expect(reference.stderr.isEmpty)

            let disassembly = try javap(["-c", "-classpath", artifact.path, "HelloKt"])
            #expect(disassembly.exitCode == 0)
            #expect(disassembly.stdout.contains("java/lang/Math.hypot"))
            #expect(disassembly.stdout.contains("java/lang/Math.log1p"))
            #expect(disassembly.stdout.contains("java/lang/Math.ulp"))
            #expect(disassembly.stdout.contains("java/lang/Math.copySign"))
            #expect(!disassembly.stdout.contains("MathKt__MathJVMKt"))

            let javaRoot = root.appendingPathComponent("java-consumer", isDirectory: true)
            try FileManager.default.createDirectory(at: javaRoot, withIntermediateDirectories: true)
            let javaSource = root.appendingPathComponent("JavaConsumer.java")
            try """
            public final class JavaConsumer {
                public static void main(String[] args) {
                    HelloKt.main();
                }
            }
            """.write(to: javaSource, atomically: true, encoding: .utf8)
            let javaCompilation = try javac(["-classpath", artifact.path + ":" + runtime, "-d", javaRoot.path, javaSource.path])
            try #require(javaCompilation.exitCode == 0, "\(javaCompilation.stderr)")
            let javaConsumer = try java(["-cp", javaRoot.path + ":" + artifact.path + ":" + runtime, "JavaConsumer"])
            #expect(javaConsumer.exitCode == 0)
            #expect(javaConsumer.stdout == reference.stdout)
            #expect(javaConsumer.stderr.isEmpty)
        }
    }

    @Test
    func externalMathCallsRejectWrongArgumentTypes() throws {
        let runtime = try m11Runtime()
        let classpath = runtime.components(separatedBy: ":")
        try withWorkspace { root in
            let result = try compile("""
            import kotlin.math.hypot
            fun main() { hypot(3.0, "4.0") }
            """, root: root, mode: .jvmJar, classpath: classpath)
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.severity == .error })
        }
    }
}
#endif

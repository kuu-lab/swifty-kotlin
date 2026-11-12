#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func platformRandomAdaptersPreserveStreamsAndIdentity() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            import java.util.Random as JavaRandom
            import kotlin.random.Random
            import kotlin.random.asJavaRandom
            import kotlin.random.asKotlinRandom

            fun main() {
                val java = JavaRandom(42L)
                val fromJava = java.asKotlinRandom()
                println(fromJava.asJavaRandom() === java)
                println(fromJava.nextInt(37))
                println(fromJava.nextLong())
                println(fromJava.nextDouble())
                val bytes = ByteArray(5)
                println(fromJava.nextBytes(bytes) === bytes)
                for (byte in bytes) println(byte.toInt())
                println(java.nextInt())

                val kotlin = Random(42)
                val fromKotlin = kotlin.asJavaRandom()
                println(fromKotlin.asKotlinRandom() === kotlin)
                println(fromKotlin.nextInt(37))
                println(fromKotlin.nextBoolean())
                fromKotlin.nextBytes(bytes)
                for (byte in bytes) println(byte.toInt())
                println(kotlin.nextInt())
                try {
                    fromKotlin.setSeed(0L)
                } catch (_: UnsupportedOperationException) {
                    println("fixed seed")
                }
            }
            """
            let file = "PlatformRandomProbe.kt"
            try source.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", [file, "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "PlatformRandomProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let precompiled = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "PlatformRandomProbeKt"])
            #expect(precompiled.exitCode == 0, "\(precompiled.stderr)")
            #expect(precompiled.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [(file, source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "PlatformRandomProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif

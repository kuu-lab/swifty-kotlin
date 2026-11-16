#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func randomABIExecutesEnumEntriesAndSeededConsumersAgainstOwnStdlib() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            import kotlin.random.Random

            enum class Theme { BLUE }
            class Last : Random() {
                override fun nextBits(bitCount: Int): Int = 0
                override fun nextInt(until: Int): Int = until - 1
            }
            fun main() {
                println(Theme.entries.random())
                println(listOf("first", "last").random(Last()))
                println(setOf("first", "last").random(Last()))
                println(Random.Default.nextInt(1))
                println(Random.nextInt(1))
                val random = Random(42)
                println(random.nextInt())
                println(random.nextInt(-13, 71))
                println(random.nextLong())
                println(random.nextDouble())
                println(Random(0x1_0000_0001L).nextInt())
                val bytes = random.nextBytes(ByteArray(4), fromIndex = 1)
                for (byte in bytes) println(byte.toInt())
                try {
                    emptyList<Int>().random(random)
                } catch (_: NoSuchElementException) {
                    println("empty")
                }
            }
            """
            try source.write(to: root.appendingPathComponent("RandomProbe.kt"), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["RandomProbe.kt", "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "RandomProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let precompiled = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "RandomProbeKt"])
            #expect(precompiled.exitCode == 0, "\(precompiled.stderr)")
            #expect(precompiled.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("RandomProbe.kt", source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "RandomProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif

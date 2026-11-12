#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func durationABIExecutesPrecompiledKotlinAgainstOwnStdlib() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            import kotlin.time.Duration
            import kotlin.time.DurationUnit
            import kotlin.time.toDuration

            fun main() {
                val zero = Duration.ZERO
                val negative = (-1250).toDuration(DurationUnit.MILLISECONDS)
                val whole = 90L.toDuration(DurationUnit.SECONDS)
                val fraction = 0.5.toDuration(DurationUnit.MICROSECONDS)
                val huge = Long.MAX_VALUE.toDuration(DurationUnit.DAYS)
                val boxed: Any = negative
                println(zero)
                println(negative.toString())
                println(negative.isNegative())
                println(negative.inWholeMilliseconds)
                println(negative.inWholeSeconds)
                println(whole.toDouble(DurationUnit.MINUTES))
                println(whole.compareTo(negative))
                println(negative == (-1250L).toDuration(DurationUnit.MILLISECONDS))
                println(negative.hashCode())
                println(boxed == negative)
                println((boxed as Duration).inWholeMilliseconds)
                println(fraction.inWholeNanoseconds)
                println(huge == Duration.INFINITE)
            }
            """
            try source.write(to: root.appendingPathComponent("DurationProbe.kt"), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["DurationProbe.kt", "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "DurationProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let candidate = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "DurationProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("DurationProbe.kt", source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let ownConsumer = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "DurationProbeKt"])
            #expect(ownConsumer.exitCode == 0, "\(ownConsumer.stderr)")
            #expect(ownConsumer.stdout == reference.stdout)
        }
    }
}
#endif

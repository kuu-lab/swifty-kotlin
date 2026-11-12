#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func instantAndClockLinkAgainstOwnStdlib() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let file = "InstantProbe.kt"
            let source = """
            import kotlin.time.Clock
            import kotlin.time.Duration
            import kotlin.time.DurationUnit
            import kotlin.time.Instant
            import kotlin.time.toDuration
            import kotlin.time.toJavaInstant
            import kotlin.time.toKotlinInstant

            fun main() {
                val parsed = Instant.parse("2026-11-13T12:34:56.123456789+09:00")
                println(parsed)
                println(parsed.epochSeconds)
                println(parsed.nanosecondsOfSecond)
                println(Instant.parseOrNull("2026-02-29T12:00:00Z"))
                val negative = Instant.fromEpochMilliseconds(-1L)
                println(negative)
                println(negative.toEpochMilliseconds())
                println(Instant.fromEpochSeconds(0L, -1))
                println(Instant.fromEpochSeconds(0L, -1L))
                println(Instant.fromEpochSeconds(0L))
                println(Instant.fromEpochSeconds(Long.MAX_VALUE).toEpochMilliseconds())
                println(Instant.fromEpochSeconds(Long.MIN_VALUE).toEpochMilliseconds())
                println(Instant.DISTANT_PAST)
                println(Instant.DISTANT_FUTURE)
                val one = 1L.toDuration(DurationUnit.NANOSECONDS)
                println(negative + one)
                println(negative - one)
                println((negative - (negative - one)).inWholeNanoseconds)
                println((negative + Duration.INFINITE).toEpochMilliseconds())
                println(negative < parsed)
                println(negative == Instant.fromEpochMilliseconds(-1L))
                println(negative.hashCode())
                println(parsed.toJavaInstant().toKotlinInstant() == parsed)
                val clock: Clock = Clock.System
                val now = clock.now()
                println(now.epochSeconds > 0L)
            }
            """
            try source.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", [file, "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "InstantProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let precompiled = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "InstantProbeKt"])
            #expect(precompiled.exitCode == 0, "\(precompiled.stderr)")
            #expect(precompiled.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [(file, source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "InstantProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif

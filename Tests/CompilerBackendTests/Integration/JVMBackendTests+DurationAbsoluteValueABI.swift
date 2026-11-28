#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func durationAbsoluteValueABIExecutesPrecompiledKotlinAgainstOwnStdlib() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            import kotlin.time.Duration
            import kotlin.time.DurationUnit
            import kotlin.time.toDuration

            fun main() {
                val negative = (-30).toDuration(DurationUnit.SECONDS)
                println(negative.absoluteValue.inWholeSeconds)
                val negativeInfinity = Double.NEGATIVE_INFINITY.toDuration(DurationUnit.SECONDS)
                println(negativeInfinity.absoluteValue == Duration.INFINITE)
            }
            """
            try source.write(to: root.appendingPathComponent("DurationAbsoluteValueProbe.kt"), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["DurationAbsoluteValueProbe.kt", "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "DurationAbsoluteValueProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let candidate = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "DurationAbsoluteValueProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("DurationAbsoluteValueProbe.kt", source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let ownConsumer = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "DurationAbsoluteValueProbeKt"])
            #expect(ownConsumer.exitCode == 0, "\(ownConsumer.stderr)")
            #expect(ownConsumer.stdout == reference.stdout)
        }
    }

    @Test
    func durationAbsoluteValueSafeCallCompilesWithoutClasspath() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import kotlin.time.Duration
            import kotlin.time.DurationUnit
            import kotlin.time.toDuration

            fun absoluteSeconds(value: Duration?): Long? = value?.absoluteValue?.inWholeSeconds
            fun absoluteOrZero(value: Duration?): Duration = value?.absoluteValue ?: 0.toDuration(DurationUnit.SECONDS)

            fun main() {
                val negative: Duration? = (-30).toDuration(DurationUnit.SECONDS)
                println(absoluteSeconds(negative))
                println(absoluteSeconds(null))
                println(absoluteOrZero(negative).inWholeSeconds)
                println(absoluteOrZero(null).inWholeSeconds)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root,
                sources: [("DurationAbsoluteValueNullableProbe.kt", source)],
                name: "duration-absolute-value-nullable.jar",
                classpath: []
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")

            let result = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "DurationAbsoluteValueNullableProbeKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "30\nnull\n30\n0\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif

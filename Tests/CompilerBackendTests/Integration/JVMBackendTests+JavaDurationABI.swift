#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaDurationConversionsMatchKotlinAndLinkPrecompiledCallers() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let file = "DurationProbe.kt"
            let source = """
            import java.time.Duration as JavaDuration
            import kotlin.time.Duration
            import kotlin.time.DurationUnit
            import kotlin.time.toDuration
            import kotlin.time.toJavaDuration
            import kotlin.time.toKotlinDuration

            fun main() {
                val negative = (-1_250_000_001L).toDuration(DurationUnit.NANOSECONDS)
                val normalized = negative.toJavaDuration()
                println(normalized.toString())
                println(normalized.toKotlinDuration().inWholeNanoseconds)
                val wide = 4_700_000_000_123L.toDuration(DurationUnit.MILLISECONDS)
                println(wide.toJavaDuration().toKotlinDuration().inWholeMilliseconds)
                println(Duration.INFINITE.toJavaDuration().getSeconds())
                println(JavaDuration.ofSeconds(Long.MIN_VALUE, 0L).toKotlinDuration().isInfinite())
            }
            """
            try source.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let referenceJar = root.appendingPathComponent("reference.jar")
            let compiled = try jvmTool("kotlinc", [file, "-d", referenceJar.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", referenceJar.path + ":" + official, "DurationProbeKt"])
            let precompiled = try java(["-Xverify:all", "-cp", referenceJar.path + ":" + own.path, "DurationProbeKt"])
            #expect(precompiled.stdout == reference.stdout)
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [(file, source)], name: "app.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "DurationProbeKt"])
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif

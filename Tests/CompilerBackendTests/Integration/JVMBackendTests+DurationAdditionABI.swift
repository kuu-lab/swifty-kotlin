#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func durationAdditionLinksWithoutClasspath(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            import kotlin.time.DurationUnit
            import kotlin.time.toDuration

            fun main() {
                println(1.toDuration(DurationUnit.NANOSECONDS) + 2.toDuration(DurationUnit.NANOSECONDS))
            }
            """, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let disassembly = try javap(["-c", "-classpath", artifact, "HelloKt"])
            // Without the text-library ABI entry the call site is emitted as an
            // instance `plus(J)J` on a long receiver and fails verification.
            #expect(disassembly.stdout.contains(#"Method kotlin/time/Duration."plus-LRDsOJo":(JJ)J"#))
        }
    }

    @Test
    func durationAdditionLinksAgainstOwnStdlibWithMixedScales() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            import kotlin.time.DurationUnit
            import kotlin.time.toDuration

            fun main() {
                val small = 17L.toDuration(DurationUnit.NANOSECONDS)
                val large = 4611686018427L.toDuration(DurationUnit.MILLISECONDS)
                val infinite = Long.MAX_VALUE.toDuration(DurationUnit.DAYS)
                val negativeInfinite = Long.MIN_VALUE.toDuration(DurationUnit.DAYS)
                println((small + small).inWholeNanoseconds)
                println((large + small).inWholeMilliseconds)
                println((large + (-4611686018426L).toDuration(DurationUnit.MILLISECONDS)).inWholeNanoseconds)
                println((small + infinite).isInfinite())
                try {
                    println(infinite + negativeInfinite)
                } catch (_: IllegalArgumentException) {
                    println("opposite infinities")
                }
            }
            """
            try source.write(to: root.appendingPathComponent("DurationPlusProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["DurationPlusProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", app.path + ":" + official, "DurationPlusProbeKt"])
            let precompiled = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "DurationPlusProbeKt"])
            #expect(precompiled.stdout == reference.stdout)

            let (candidate, exit, diagnostics) = try m22Build(root: root, sources: [("DurationPlusProbe.kt", source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", candidate.path + ":" + own.path, "DurationPlusProbeKt"])
            #expect(run.stdout == reference.stdout)
        }
    }
}
#endif

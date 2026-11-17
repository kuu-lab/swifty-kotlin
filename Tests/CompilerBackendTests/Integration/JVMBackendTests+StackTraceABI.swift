#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func stackTraceABIIncludesFramesCausesAndSuppressedExceptions() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let file = "StackTraceProbe.kt"
            let source = """
            fun main() {
                val error = IllegalStateException("primary", IllegalArgumentException("cause"))
                error.addSuppressed(IllegalStateException("suppressed"))
                val trace = error.stackTraceToString()
                println(trace.contains("java.lang.IllegalStateException: primary"))
                println(trace.contains("StackTraceProbeKt.main("))
                println(trace.contains("Suppressed: java.lang.IllegalStateException: suppressed"))
                println(trace.contains("Caused by: java.lang.IllegalArgumentException: cause"))
            }
            """
            try source.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", [file, "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "StackTraceProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            #expect(reference.stdout == "true\ntrue\ntrue\ntrue\n")
            let precompiled = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "StackTraceProbeKt"])
            #expect(precompiled.exitCode == 0, "\(precompiled.stderr)")
            #expect(precompiled.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [(file, source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "StackTraceProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif

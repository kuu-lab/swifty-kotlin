#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func inputStreamReadBytesLinksAndLeavesStreamOpen() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let file = "ByteStreamsProbe.kt"
            let source = """
            import java.io.ByteArrayInputStream
            import java.io.InputStream

            class TrackingStream(bytes: ByteArray) : ByteArrayInputStream(bytes) {
                var closed = false
                override fun close() { closed = true }
            }

            fun read(stream: InputStream): ByteArray = stream.readBytes()

            fun main() {
                val input = TrackingStream(ByteArray(16401) { (it and 255).toByte() })
                val bytes = read(input)
                println(bytes.size)
                println(bytes[8191].toInt())
                println(bytes[8192].toInt())
                println(bytes[16400].toInt())
                println(read(input).size)
                println(input.closed)
            }
            """
            try source.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", [file, "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "ByteStreamsProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            #expect(reference.stdout == "16401\n-1\n0\n16\n0\nfalse\n")
            let precompiled = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "ByteStreamsProbeKt"])
            #expect(precompiled.exitCode == 0, "\(precompiled.stderr)")
            #expect(precompiled.stdout == reference.stdout)

            let candidateSource = """
            import java.io.InputStream
            fun readCandidate(stream: InputStream): ByteArray = stream.readBytes()
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Candidate.kt", candidateSource)], name: "candidate.jar", classpath: [own.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let driver = source.replacingOccurrences(of: "stream.readBytes()", with: "readCandidate(stream)")
            try driver.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let driverJar = root.appendingPathComponent("driver.jar")
            let compiledDriver = try jvmTool("kotlinc", [file, "-cp", app.path, "-d", driverJar.path], root: root)
            try #require(compiledDriver.exitCode == 0, "\(compiledDriver.stderr)")
            let candidate = try java(["-Xverify:all", "-cp", driverJar.path + ":" + app.path + ":" + own.path, "ByteStreamsProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif

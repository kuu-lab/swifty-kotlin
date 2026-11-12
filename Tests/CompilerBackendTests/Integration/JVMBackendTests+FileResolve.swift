#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func fileResolveStringLinksAgainstOwnStdlib() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            import java.io.File

            fun main() {
                println(File("parent").resolve("child").path)
                println(File("").resolve("child").path)
                println(File("parent").resolve("").path)
                println(File("parent").resolve("/absolute").path)
                println(File("/").resolve("child").path)
                println(File("parent").resolve("../child").path)
                println(File("parent").resolve("C:").path)
                println(File("parent").resolve("name:part").path)
                println(File("parent", "nested").resolve("child").path)
            }
            """
            try source.write(to: root.appendingPathComponent("FilesProbe.kt"), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["FilesProbe.kt", "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "FilesProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let precompiled = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "FilesProbeKt"])
            #expect(precompiled.exitCode == 0, "\(precompiled.stderr)")
            #expect(precompiled.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("FilesProbe.kt", source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "FilesProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif

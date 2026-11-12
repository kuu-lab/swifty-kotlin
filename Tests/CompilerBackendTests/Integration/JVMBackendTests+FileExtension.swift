#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func fileExtensionLinksAgainstOwnStdlibAndUsesTheFileName() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let source = """
            import java.io.File
            fun main() {
                println(File("name").extension)
                println(File("dir.txt/name").extension)
                println(File("settings.preferences_pb").extension)
                println(File("archive.tar.gz").extension)
                println(File("name.").extension)
                println(File(".profile").extension)
            }
            """
            try source.write(to: root.appendingPathComponent("FileExtensionProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["FileExtensionProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", app.path + ":" + official, "FileExtensionProbeKt"])
            let precompiled = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "FileExtensionProbeKt"])
            #expect(precompiled.stdout == reference.stdout)

            let (candidateApp, exit, diagnostics) = try m22Build(root: root, sources: [("FileExtensionProbe.kt", source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", candidateApp.path + ":" + own.path, "FileExtensionProbeKt"])
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif

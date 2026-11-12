#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func byteArrayDecodeToStringLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                println(byteArrayOf(65, -29, -127, -126).decodeToString())
                println(byteArrayOf(-61, 40).decodeToString())
                println(byteArrayOf().decodeToString().length)
                println("Aあ".encodeToByteArray().contentToString())
                println("".encodeToByteArray().size)
            }
            """
            try source.write(to: root.appendingPathComponent("Decode.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Decode.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "DecodeKt"])
            #expect(run.stdout == "Aあ\n�(\n0\n[65, -29, -127, -126]\n0\n")

            let (candidate, exit, diagnostics) = try m22Build(root: root, sources: [("Decode.kt", source)], name: "candidate.jar", classpath: [stdlib.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidateRun = try java(["-Xverify:all", "-cp", candidate.path + ":" + stdlib.path, "DecodeKt"])
            #expect(candidateRun.stdout == run.stdout)
        }
    }
}
#endif

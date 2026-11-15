#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func stringCompanionLinksAgainstOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun describe(companion: String.Companion) = companion.javaClass.name
            fun main() {
                println(describe(String))
                println(String.Companion === String)
            }
            """
            try source.write(to: root.appendingPathComponent("StringProbe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["StringProbe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "StringProbeKt"])
            #expect(run.stdout == "kotlin.jvm.internal.StringCompanionObject\ntrue\n")
        }
    }
}
#endif

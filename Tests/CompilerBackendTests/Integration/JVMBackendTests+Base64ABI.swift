#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledBase64UsesOwnStdlibWithDefaultArguments() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import kotlin.io.encoding.Base64
            fun main() {
                println(Base64.decode("44GC").decodeToString())
                println(Base64.decode("!QQ==!", startIndex = 1, endIndex = 5).decodeToString())
                println(Base64.encodeToByteArray(byteArrayOf(65)).decodeToString())
                println(Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT).encode(byteArrayOf(-1)))
                try {
                    Base64.decode("QR==")
                } catch (_: IllegalArgumentException) {
                    println("invalid")
                }
            }
            """
            try source.write(to: root.appendingPathComponent("Base64Probe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Base64Probe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + stdlib.path, "Base64ProbeKt"])
            #expect(run.stdout == "あ\nA\nQQ==\n_w\ninvalid\n")
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func inputStreamReaderUsesRequestedCharsetAndReadsToEnd() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package fixture;
            public class Streams {
                public static java.io.InputStream fromBytes(byte[] bytes) {
                    return new java.io.ByteArrayInputStream(bytes);
                }
            }
            """.write(to: root.appendingPathComponent("Streams.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Streams.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import fixture.Streams
                import java.io.InputStreamReader

                fun main() {
                    val utf8: InputStreamReader = Streams.fromBytes(byteArrayOf(-61, -87)).reader()
                    println(utf8.readText())
                    println(utf8.readText().length)
                    val latin1 = Streams.fromBytes(ByteArray(16401) { -23 }).reader(Charsets.ISO_8859_1)
                    val text = latin1.use { it.readText() }
                    println(text.length)
                    println(text[8192])
                }
                """)],
                name: "app.jar", classpath: [own.path, classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + own.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "é\n0\n16401\né\n")
        }
    }
}
#endif

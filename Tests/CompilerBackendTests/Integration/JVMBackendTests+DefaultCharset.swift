#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// KUU-4649: `Charset.defaultCharset()` must resolve against the JVM JDK
    /// platform declaration of `java.nio.charset.Charset`, not only `forName`.
    @Test
    func charsetDefaultCharsetResolvesAndRunsOnJvm() throws {
        try withWorkspace { root in
            let source = """
            import java.nio.charset.Charset

            fun main() {
                println(Charset.defaultCharset().name())
                val charset: Charset = Charset.defaultCharset()
                println(charset.name() == Charset.forName("UTF-8").name())
            }
            """
            let (app, status, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "default-charset.jar"
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Dfile.encoding=UTF-8", "-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "UTF-8\ntrue\n")
        }
    }
}
#endif

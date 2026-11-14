#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func inputStreamMembersUseJDKByteArrayDescriptors() throws {
        try withWorkspace { root in
            let classes = root.appendingPathComponent("classes").path
            let main = """
            fun readAsset(stream: java.io.InputStream) {
                val bytes = ByteArray(stream.available())
                println(stream.read())
                println(stream.read(bytes, 1, 1))
                println(stream.read(bytes))
                println(bytes[0])
                println(bytes[1])
                stream.close()
            }
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", main)], name: "app.jar")
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            try """
            import java.io.ByteArrayInputStream;
            public class Reader {
                public static void main(String[] args) {
                    MainKt.readAsset(new ByteArrayInputStream(new byte[] { 65, 66, 67 }));
                }
            }
            """.write(to: root.appendingPathComponent("Reader.java"), atomically: true, encoding: .utf8)
            let reader = try jvmTool("javac", ["-cp", app.path, "-d", classes, "Reader.java"], root: root)
            try #require(reader.exitCode == 0, "\(reader.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "Reader"])
            #expect(run.stdout == "65\n1\n1\n67\n66\n")
        }
    }
}
#endif

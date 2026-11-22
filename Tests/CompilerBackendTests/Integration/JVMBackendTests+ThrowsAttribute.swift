#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func throwsClassLiteralsReachJavaAndReflection() throws {
        try withWorkspace { root in
            let sources = [
                ("Other.kt", "class Other"),
                ("Api.kt", """
                 package fixture
                 class Checked : Exception()
                 @Throws(Checked::class, IllegalStateException::class)
                 fun read(): String = "read"
                 """),
            ]
            let (app, status, diagnostics) = try m22Build(root: root, sources: sources, name: "app.jar")
            try #require(status == 0, "\(diagnostics.map(\.message))")
            try """
            public class Reader {
                public static void main(String[] args) throws Exception {
                    for (Class<?> type : fixture.ApiKt.class.getMethod("read").getExceptionTypes()) {
                        System.out.println(type.getName());
                    }
                    try { System.out.println(fixture.ApiKt.read()); }
                    catch (fixture.Checked failure) { throw new AssertionError(failure); }
                }
            }
            """.write(to: root.appendingPathComponent("Reader.java"), atomically: true, encoding: .utf8)
            let compiler = try jvmTool("javac", ["-cp", app.path, "Reader.java"], root: root)
            try #require(compiler.exitCode == 0, "\(compiler.stderr)")
            let result = try java(["-Xverify:all", "-cp", root.path + ":" + app.path, "Reader"])
            #expect(result.stdout == "fixture.Checked\njava.lang.IllegalStateException\nread\n")
        }
    }
}
#endif

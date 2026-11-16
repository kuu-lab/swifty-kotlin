#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmImportedNestedClassesExposePublicNoArgumentConstructors() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            package api;
            public class Outer {
                public static class Builder {
                    public Builder() {}
                    public String label() { return "builder"; }
                }

                public static class Hidden {
                    private Hidden() {}
                    public Hidden(int value) {}
                }
            }
            """.write(to: root.appendingPathComponent("Outer.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["--release", "8", "-d", "dependency", "Outer.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let dependency = root.appendingPathComponent("dependency").path
            let classpath = [library.path, dependency]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", "import api.Outer\nfun main() { println(Outer.Builder().label()) }")],
                name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", ([app.path] + classpath).joined(separator: ":"), "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "builder\n")
            let (_, rejected, errors) = try m22Build(
                root: root, sources: [("Bad.kt", "import api.Outer\nfun bad() = Outer.Hidden()")],
                name: "bad.jar", classpath: classpath
            )
            #expect(rejected != 0)
            #expect(errors.contains { $0.severity == .error })
        }
    }
}
#endif

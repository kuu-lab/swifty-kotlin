#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsAnnotationNestedInClasspathAnnotation() throws {
        try withWorkspace { root in
            let dependency = """
            package fixture;
            import java.lang.annotation.Retention;
            import java.lang.annotation.RetentionPolicy;
            public @interface DependencyGraph {
                @Retention(RetentionPolicy.RUNTIME)
                @interface Factory { String value(); }
            }
            """
            try dependency.write(to: root.appendingPathComponent("DependencyGraph.java"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("javac", ["--release", "8", "-d", "dependency", "DependencyGraph.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let classpath = [root.appendingPathComponent("dependency").path]
            let source = """
            import fixture.DependencyGraph
            @DependencyGraph.Factory("factory")
            class Subject
            """
            let (app, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: classpath)
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let reader = """
            import fixture.DependencyGraph;
            public class Reader {
                public static void main(String[] args) throws Exception {
                    System.out.println(Class.forName("Subject").getAnnotation(DependencyGraph.Factory.class).value());
                }
            }
            """
            try reader.write(to: root.appendingPathComponent("Reader.java"), atomically: true, encoding: .utf8)
            let runtime = ([app.path] + classpath).joined(separator: ":")
            let readerBuild = try jvmTool("javac", ["-cp", runtime, "-d", "dependency", "Reader.java"], root: root)
            try #require(readerBuild.exitCode == 0, "\(readerBuild.stderr)")
            let run = try java(["-Xverify:all", "-cp", runtime, "Reader"])
            #expect(run.exitCode == 0)
            #expect(run.stdout == "factory\n")
        }
    }
}
#endif

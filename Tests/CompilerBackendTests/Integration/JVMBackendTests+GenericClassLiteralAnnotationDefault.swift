#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func genericClassLiteralAnnotationDefaultIsImportedWithoutTypeArguments() throws {
        try withWorkspace { root in
            let sources = [
                "Strategy.java": "package dep; public interface Strategy<T> {}",
                "Marker.java": """
                package dep;
                import java.lang.annotation.*;
                @Retention(RetentionPolicy.RUNTIME)
                public @interface Marker { Class<? extends Strategy> with() default Strategy.class; }
                """,
            ]
            for (name, contents) in sources {
                try contents.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            let classes = root.appendingPathComponent("deps")
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
            let compiled = try jvmTool("javac", ["--release", "8", "-d", "deps", "Strategy.java", "Marker.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
                import dep.Marker

                @Marker
                class Annotated

                fun main() { println("compiled") }
                """
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: [classes.path])
            #expect(exitCode == 0, "\(diagnostics.map(\.message))")
        }
    }
}
#endif

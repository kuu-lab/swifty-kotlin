#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaAnnotationRootImportsAsOrdinaryInterface() throws {
        try withWorkspace { root in
            let javaPackage = root.appendingPathComponent("java/lang/annotation")
            try FileManager.default.createDirectory(at: javaPackage, withIntermediateDirectories: true)
            let annotation = javaPackage.appendingPathComponent("Annotation.java")
            try """
            package java.lang.annotation;
            public interface Annotation {
                boolean equals(Object other);
                int hashCode();
                String toString();
                Class<? extends Annotation> annotationType();
            }
            """.write(to: annotation, atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("deps")
            let compiled = try jvmTool("javac", ["--release", "8", "-d", dependency.path, annotation.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let source = """
            import java.lang.annotation.Annotation
            fun typeOf(annotation: Annotation): Class<*> = annotation.annotationType()
            """
            let (_, exit, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [dependency.path])
            #expect(exit == 0, "\(diagnostics.map(\.message))")
        }
    }
}
#endif

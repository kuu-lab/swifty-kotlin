#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedJavaAnnotationArrayValueAcceptsVarargs() throws {
        try withWorkspace { root in
            let declaration = """
            package fixture;
            @java.lang.annotation.Retention(java.lang.annotation.RetentionPolicy.RUNTIME)
            public @interface Components {
                Class<?>[] value();
            }
            """
            try declaration.write(to: root.appendingPathComponent("Components.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency")
            let javac = try jvmTool("javac", ["-d", dependency.path, "Components.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Components
            @Components(String::class)
            class Single
            @Components(String::class, Long::class)
            class Multiple
            @Components(value = [String::class])
            class Named
            @Components
            class Empty
            """
            let (app, status, diagnostics) = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [dependency.path])
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let consumer = """
            public final class ReadAnnotations {
                public static void main(String[] args) {
                    for (Class<?> type : new Class<?>[] { Single.class, Multiple.class, Named.class, Empty.class }) {
                        fixture.Components annotation = type.getAnnotation(fixture.Components.class);
                        System.out.println(annotation.value().length);
                    }
                }
            }
            """
            try consumer.write(to: root.appendingPathComponent("ReadAnnotations.java"), atomically: true, encoding: .utf8)
            let classpath = app.path + ":" + dependency.path
            let compiled = try jvmTool("javac", ["-cp", classpath, "ReadAnnotations.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let result = try java(["-cp", root.path + ":" + classpath, "ReadAnnotations"])
            #expect(result.stdout == "1\n2\n1\n0\n")
        }
    }
}
#endif

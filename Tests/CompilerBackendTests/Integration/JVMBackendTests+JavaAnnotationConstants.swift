#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsJavaAnnotationConstantsAsAnnotationArguments() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.lang.annotation.Retention;
            import java.lang.annotation.RetentionPolicy;

            @Retention(RetentionPolicy.RUNTIME)
            public @interface Entity {
                @Retention(RetentionPolicy.RUNTIME)
                @interface Key {
                    int CASCADE = 5;
                    int onDelete() default 1;
                }
                Key[] foreignKeys();
            }
            """.write(to: root.appendingPathComponent("Entity.java"), atomically: true, encoding: .utf8)
            let dependency = root.appendingPathComponent("dependency").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", dependency, "Entity.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let source = """
            import fixture.Entity
            import fixture.Entity.Key.CASCADE

            @Entity(foreignKeys = [Entity.Key(onDelete = CASCADE), Entity.Key(onDelete = Entity.Key.CASCADE), Entity.Key()])
            class Subject
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [dependency]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            try """
            import fixture.Entity;
            public class Reader {
                public static void main(String[] args) throws Exception {
                    for (Entity.Key key : Class.forName("Subject").getAnnotation(Entity.class).foreignKeys()) {
                        System.out.println(key.onDelete());
                    }
                }
            }
            """.write(to: root.appendingPathComponent("Reader.java"), atomically: true, encoding: .utf8)
            let reader = try jvmTool("javac", ["-cp", dependency, "-d", dependency, "Reader.java"], root: root)
            try #require(reader.exitCode == 0, "\(reader.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + dependency, "Reader"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "5\n5\n1\n")
        }
    }
}
#endif

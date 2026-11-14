#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func parameterAnnotationClassLiteralResolvesInItsOwnFile() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.lang.annotation.ElementType;
            import java.lang.annotation.Retention;
            import java.lang.annotation.RetentionPolicy;
            import java.lang.annotation.Target;
            @Retention(RetentionPolicy.RUNTIME)
            @Target(ElementType.PARAMETER)
            public @interface Relation { Class<?> entity(); }
            """.write(to: root.appendingPathComponent("Relation.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes")
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes.path, "Relation.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let sources = [
                ("Other.kt", "package other\nclass Target"),
                ("Target.kt", "package model\nclass Target"),
                ("Record.kt", """
                 package records
                 import fixture.Relation
                 import model.Target
                 class Record(@param:Relation(entity = Target::class) val value: String)
                 """),
            ]
            let (app, exit, diagnostics) = try m22Build(root: root, sources: sources, name: "app.jar", classpath: [classes.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            try """
            import fixture.Relation;
            public class Reader {
                public static void main(String[] args) throws Exception {
                    System.out.println(Class.forName("records.Record").getConstructor(String.class)
                        .getParameters()[0].getAnnotation(Relation.class).entity().getName());
                }
            }
            """.write(to: root.appendingPathComponent("Reader.java"), atomically: true, encoding: .utf8)
            let reader = try jvmTool("javac", ["-cp", classes.path, "-d", classes.path, "Reader.java"], root: root)
            try #require(reader.exitCode == 0, "\(reader.stderr)")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes.path, "Reader"])
            #expect(run.stdout == "model.Target\n")
        }
    }
}
#endif

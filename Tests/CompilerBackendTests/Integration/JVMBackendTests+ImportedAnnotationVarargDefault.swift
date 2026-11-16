#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func emptyJavaAnnotationVarargDefaultRemainsOptional() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.lang.annotation.Retention;
            import java.lang.annotation.RetentionPolicy;
            @Retention(RetentionPolicy.RUNTIME)
            public @interface Category { Class<?>[] value() default {}; }
            """.write(to: root.appendingPathComponent("Category.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public class Counts {
                public static int size(Class<?> type) {
                    return type.getAnnotation(Category.class).value().length;
                }
            }
            """.write(to: root.appendingPathComponent("Counts.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Category.java", "Counts.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import fixture.Category
                import fixture.Counts
                @Category class Without
                @Category(String::class) class With
                fun main() {
                    println(Counts.size(Without::class.java))
                    println(Counts.size(With::class.java))
                }
                """)],
                name: "app.jar", classpath: [classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "0\n1\n")
        }
    }
}
#endif

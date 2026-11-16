#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaAnnotationCanDefaultToPackagePrivateClass() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.lang.annotation.Retention;
            import java.lang.annotation.RetentionPolicy;
            class DefaultTarget {}
            @Retention(RetentionPolicy.RUNTIME)
            public @interface Config {
                Class<?> target() default DefaultTarget.class;
            }
            """.write(to: root.appendingPathComponent("Config.java"), atomically: true, encoding: .utf8)
            try """
            package fixture;
            public class Inspector {
                public static String target(Class<?> type) {
                    return type.getAnnotation(Config.class).target().getName();
                }
            }
            """.write(to: root.appendingPathComponent("Inspector.java"), atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes").path
            let javac = try jvmTool("javac", ["--release", "8", "-d", classes, "Config.java", "Inspector.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import fixture.Config
                import fixture.Inspector
                @Config class Defaulted
                @Config(target = String::class) class Explicit
                fun main() {
                    println(Inspector.target(Defaulted::class.java))
                    println(Inspector.target(Explicit::class.java))
                }
                """)],
                name: "app.jar", classpath: [classes]
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + classes, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "fixture.DefaultTarget\njava.lang.String\n")
        }
    }
}
#endif

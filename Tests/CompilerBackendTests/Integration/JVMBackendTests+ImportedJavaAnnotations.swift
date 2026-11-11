#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsJavaFieldAnnotationDefaults() throws {
        try withWorkspace { root in
            try """
            package dependency;

            import java.lang.annotation.ElementType;
            import java.lang.annotation.Retention;
            import java.lang.annotation.RetentionPolicy;
            import java.lang.annotation.Target;

            @Retention(RetentionPolicy.RUNTIME)
            @Target(ElementType.FIELD)
            public @interface Option {
                String[] names();
                Class<?> converter() default Object.class;
                boolean required() default false;
            }
            """.write(to: root.appendingPathComponent("Option.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Option.java"], root: root)
            let dependencies = root.appendingPathComponent("deps").path
            let result = try compile("""
            import dependency.Option

            class Options {
                @Option(names = ["--verbose", "-v"])
                var verbose: Boolean = false
            }
            """, root: root, mode: .jvmJar, classpath: [dependencies])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            try """
            import dependency.Option;

            public class ReadOptions {
                public static void main(String[] args) throws ReflectiveOperationException {
                    Option option = Options.class.getDeclaredField("verbose").getAnnotation(Option.class);
                    System.out.println(String.join(",", option.names()));
                    System.out.println(option.converter().getName());
                    System.out.println(option.required());
                }
            }
            """.write(to: root.appendingPathComponent("ReadOptions.java"), atomically: true, encoding: .utf8)
            let classpath = root.appendingPathComponent("hello.jar").path + ":" + dependencies
            _ = try jvmTool("javac", ["--release", "8", "-cp", classpath, "ReadOptions.java"], root: root)
            let execution = try java(["-cp", root.path + ":" + classpath, "ReadOptions"])
            #expect(execution.stdout == "--verbose,-v\njava.lang.Object\nfalse\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

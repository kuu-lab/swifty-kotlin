#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func externalAnnotationPreservesLongMinimumDefault() throws {
        try withWorkspace { root in
            try """
            package fixture;
            import java.lang.annotation.*;
            @Retention(RetentionPolicy.RUNTIME)
            public @interface Limit {
                long min() default Long.MIN_VALUE;
                long max() default Long.MAX_VALUE;
            }
            """.write(to: root.appendingPathComponent("Limit.java"), atomically: true, encoding: .utf8)
            let dependency = try jvmTool("javac", ["--release", "8", "-d", "deps", "Limit.java"], root: root)
            try #require(dependency.exitCode == 0, "\(dependency.stderr)")

            let dependencies = root.appendingPathComponent("deps").path
            let result = try compile("""
            import fixture.Limit

            @Limit
            class Sample
            """, root: root, mode: .jvmJar, classpath: [dependencies])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            try """
            public class ReadLimit {
                public static void main(String[] args) {
                    fixture.Limit limit = Sample.class.getAnnotation(fixture.Limit.class);
                    System.out.println(limit.min());
                    System.out.println(limit.max());
                }
            }
            """.write(to: root.appendingPathComponent("ReadLimit.java"), atomically: true, encoding: .utf8)
            let classpath = root.appendingPathComponent("hello.jar").path + ":" + dependencies
            let reader = try jvmTool("javac", ["-cp", classpath, "-d", "deps", "ReadLimit.java"], root: root)
            try #require(reader.exitCode == 0, "\(reader.stderr)")
            let execution = try java(["-Xverify:all", "-cp", classpath, "ReadLimit"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "-9223372036854775808\n9223372036854775807\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

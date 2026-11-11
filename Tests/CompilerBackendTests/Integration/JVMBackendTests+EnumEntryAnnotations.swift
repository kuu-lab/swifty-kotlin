#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func enumEntryAnnotationsAreEmittedOnJvmFields() throws {
        try withWorkspace { root in
            try runM11("""
            @Target(AnnotationTarget.FIELD)
            @Retention(AnnotationRetention.RUNTIME)
            annotation class Flag
            enum class Choice { @Flag FIRST, SECOND }
            fun main() { println(Choice.FIRST.name) }
            """, expected: "FIRST\n", mode: .jvmJar, root: root)

            try """
            import java.lang.annotation.Annotation;
            import java.lang.reflect.Field;

            public class EnumFieldReflection {
                private static boolean hasFlag(Field field) {
                    for (Annotation annotation : field.getDeclaredAnnotations()) {
                        if (annotation.annotationType().getName().equals("Flag")) return true;
                    }
                    return false;
                }

                public static void main(String[] args) throws Exception {
                    Class<?> choice = Class.forName("Choice");
                    System.out.println(hasFlag(choice.getField("FIRST")));
                    System.out.println(hasFlag(choice.getField("SECOND")));
                }
            }
            """.write(to: root.appendingPathComponent("EnumFieldReflection.java"), atomically: true, encoding: .utf8)
            let reflectionCompile = try javac(["-d", root.path, root.appendingPathComponent("EnumFieldReflection.java").path])
            try #require(reflectionCompile.exitCode == 0, "\(reflectionCompile.stderr)")

            let runtime = try m11Runtime()
            let reflectionClasspath = root.path
            let generated = try java([
                "-cp", root.appendingPathComponent("hello.jar").path + ":" + runtime + ":" + reflectionClasspath,
                "EnumFieldReflection",
            ])
            let reference = try java([
                "-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime + ":" + reflectionClasspath,
                "EnumFieldReflection",
            ])
            #expect(generated.exitCode == 0, "\(generated.stderr)")
            #expect(reference.exitCode == 0, "\(reference.stderr)")
            #expect(generated.stdout == "true\nfalse\n")
            #expect(generated.stdout == reference.stdout)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func receiverAnnotationIsEmittedOnJvmExtensionParameter() throws {
        let source = """
        @Target(AnnotationTarget.VALUE_PARAMETER)
        @Retention(AnnotationRetention.RUNTIME)
        annotation class Marker

        fun @receiver:Marker String.head(): Char = this[0]
        fun String.tail(): Char = this[1]

        fun main() {
            println("ok".head())
            println("ok".tail())
        }
        """

        try withWorkspace { root in
            let result = try compile(
                source,
                root: root,
                mode: .jvmJar,
                includeJVMRuntime: true
            )
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let jar = root.appendingPathComponent("hello.jar")
            let execution = try java(["-Xverify:all", "-jar", jar.path])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "o\nk\n")
            #expect(execution.stderr.isEmpty)

            let inspector = root.appendingPathComponent("InspectReceiver.java")
            try """
            import java.lang.annotation.Retention;
            import java.lang.annotation.RetentionPolicy;
            import java.lang.reflect.Method;

            public class InspectReceiver {
                public static void main(String[] args) throws Exception {
                    if (Marker.class.getAnnotation(Retention.class).value() != RetentionPolicy.RUNTIME) {
                        throw new AssertionError("Marker retention");
                    }
                    Method head = HelloKt.class.getDeclaredMethod("head", String.class);
                    Method tail = HelloKt.class.getDeclaredMethod("tail", String.class);
                    if (head.getParameterAnnotations().length != 1
                            || head.getParameterAnnotations()[0].length != 1
                            || head.getParameterAnnotations()[0][0].annotationType() != Marker.class) {
                        throw new AssertionError("receiver annotation missing from parameter 0");
                    }
                    if (tail.getParameterAnnotations().length != 1
                            || tail.getParameterAnnotations()[0].length != 0) {
                        throw new AssertionError("unannotated extension receiver changed");
                    }
                    System.out.println("receiver=Marker; control=none");
                }
            }
            """.write(to: inspector, atomically: true, encoding: .utf8)

            let compileInspector = try javac(["-cp", jar.path, "-d", root.path, inspector.path])
            try #require(compileInspector.exitCode == 0, "\(compileInspector.stderr)")
            let reflection = try java(["-cp", jar.path + ":" + root.path, "InspectReceiver"])
            #expect(reflection.exitCode == 0, "\(reflection.stderr)")
            #expect(reflection.stdout == "receiver=Marker; control=none\n")
            #expect(reflection.stderr.isEmpty)
        }
    }
}
#endif

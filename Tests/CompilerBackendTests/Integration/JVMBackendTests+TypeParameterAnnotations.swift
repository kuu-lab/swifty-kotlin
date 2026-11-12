#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func typeParameterAnnotationsMatchKotlincJavaReflection() throws {
        let source = """
        @Target(AnnotationTarget.TYPE_PARAMETER)
        @Retention(AnnotationRetention.RUNTIME)
        annotation class Mark

        @Target(AnnotationTarget.TYPE_PARAMETER)
        @Retention(AnnotationRetention.BINARY)
        annotation class BinaryMark

        class Box<@Mark T>(val value: T)
        class OffsetBox<T, @Mark U>(val first: T, val second: U)
        class Plain<T>(val value: T)
        class BinaryBox<@BinaryMark T>(val value: T)
        class MethodBox { fun <@Mark T> echo(value: T): T = value }
        fun main() {}
        """
        let probe = """
        import java.lang.annotation.Target;
        import java.lang.reflect.Method;

        public class Probe {
            public static void main(String[] args) throws Exception {
                Target target = Class.forName("Mark").getAnnotation(Target.class);
                System.out.println(target.value()[0].name());
                System.out.println(Class.forName("Box").getTypeParameters()[0].getAnnotations().length);
                System.out.println(Class.forName("Plain").getTypeParameters()[0].getAnnotations().length);
                System.out.println(Class.forName("OffsetBox").getTypeParameters()[0].getAnnotations().length);
                System.out.println(Class.forName("OffsetBox").getTypeParameters()[1].getAnnotations().length);
                Method method = Class.forName("MethodBox").getDeclaredMethod("echo", Object.class);
                System.out.println(method.getTypeParameters()[0].getAnnotations().length);
            }
        }
        """
        let expected = "TYPE_PARAMETER\n1\n0\n0\n1\n1\n"

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let compiled = try compile(source, root: root, mode: .jvmJar)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar")

            let probeSource = root.appendingPathComponent("Probe.java")
            try probe.write(to: probeSource, atomically: true, encoding: .utf8)
            let candidateProbeClasses = root.appendingPathComponent("candidate-probe-classes")
            try FileManager.default.createDirectory(at: candidateProbeClasses, withIntermediateDirectories: true)
            let candidateProbeCompile = try javac([
                "-classpath", jar.path + ":" + runtime,
                "-d", candidateProbeClasses.path,
                probeSource.path,
            ])
            try #require(candidateProbeCompile.exitCode == 0)
            let candidateReflection = try java([
                "-classpath", candidateProbeClasses.path + ":" + jar.path + ":" + runtime,
                "Probe",
            ])
            #expect(candidateReflection.exitCode == 0)
            #expect(candidateReflection.stdout == expected)
            #expect(candidateReflection.stderr.isEmpty)

            let visibleAttribute = try javap(["-v", "-classpath", jar.path, "Box"])
            #expect(visibleAttribute.exitCode == 0)
            #expect(visibleAttribute.stdout.contains("RuntimeVisibleTypeAnnotations"))
            let invisibleAttribute = try javap(["-v", "-classpath", jar.path, "BinaryBox"])
            #expect(invisibleAttribute.exitCode == 0)
            #expect(invisibleAttribute.stdout.contains("RuntimeInvisibleTypeAnnotations"))

            let referenceCompile = try jvmTool(
                "kotlinc", ["-classpath", runtime, "hello.kt", "-d", "reference.jar"], root: root
            )
            try #require(referenceCompile.exitCode == 0)
            let referenceJar = root.appendingPathComponent("reference.jar")
            let referenceProbeClasses = root.appendingPathComponent("reference-probe-classes")
            try FileManager.default.createDirectory(at: referenceProbeClasses, withIntermediateDirectories: true)
            let referenceProbeCompile = try javac([
                "-classpath", referenceJar.path + ":" + runtime,
                "-d", referenceProbeClasses.path,
                probeSource.path,
            ])
            try #require(referenceProbeCompile.exitCode == 0)
            let referenceReflection = try java([
                "-classpath", referenceProbeClasses.path + ":" + referenceJar.path + ":" + runtime,
                "Probe",
            ])
            #expect(referenceReflection.exitCode == 0)
            #expect(referenceReflection.stdout == expected)
            #expect(candidateReflection.stdout == referenceReflection.stdout)
            #expect(referenceReflection.stderr.isEmpty)
        }
    }

    @Test
    func typeParameterAnnotationsRejectIncompatibleTargets() throws {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassOnly
        class Invalid<@ClassOnly T>(val value: T)
        """

        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: .jvmJar)
            #expect(compiled.0 != 0)
            #expect(compiled.1.contains { $0.message.contains("not applicable to a type parameter") })

            do {
                _ = try jvmTool("kotlinc", ["hello.kt", "-d", "invalid.jar"], root: root)
                Issue.record("Expected kotlinc to reject the incompatible type-parameter annotation target")
            } catch let CommandRunnerError.nonZeroExit(reference) {
                #expect(reference.exitCode != 0)
            }
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func delegateUseSiteAnnotationIsEmittedOnDelegateField() throws {
        try withWorkspace { root in
            let source = #"""
            @Target(AnnotationTarget.FIELD)
            @Retention(AnnotationRetention.RUNTIME)
            annotation class Marker

            class Box {
                @delegate:Marker val answer: Int by lazy { 42 }
                @field:Marker val direct: Int = 7
            }

            fun main() { println(Box().answer) }
            """#
            let runtime = try m11Runtime()
            let classpath = runtime.components(separatedBy: ":")
            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: classpath)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let artifact = root.appendingPathComponent("hello.jar").path
            let generated = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(generated.exitCode == 0, "\(generated.stderr)")
            #expect(generated.stdout == "42\n")
            #expect(generated.stderr.isEmpty)

            let probe = root.appendingPathComponent("DelegateAnnotationProbe.java")
            try """
            public class DelegateAnnotationProbe {
                public static void main(String[] args) throws ReflectiveOperationException {
                    if (new Box().getAnswer() != 42) throw new AssertionError("delegated property value changed");
                    if (Box.class.getDeclaredField("answer$delegate").getAnnotation(Marker.class) == null) {
                        throw new AssertionError("delegate field is missing Marker");
                    }
                    if (Box.class.getDeclaredField("direct").getAnnotation(Marker.class) == null) {
                        throw new AssertionError("ordinary backing field is missing Marker");
                    }
                    if (Box.class.getDeclaredMethod("getAnswer").getAnnotation(Marker.class) != null) {
                        throw new AssertionError("Marker was emitted on the getter");
                    }
                    System.out.println("reflection-ok");
                }
            }
            """.write(to: probe, atomically: true, encoding: .utf8)
            let javaCompile = try javac(["-cp", artifact + ":" + runtime, "-d", root.path, probe.path])
            try #require(javaCompile.exitCode == 0, "\(javaCompile.stderr)")
            let generatedReflection = try java(["-cp", artifact + ":" + runtime + ":" + root.path, "DelegateAnnotationProbe"])
            #expect(generatedReflection.exitCode == 0, "\(generatedReflection.stderr)")
            #expect(generatedReflection.stdout == "reflection-ok\n")

            let reference = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let referenceArtifact = root.appendingPathComponent("reference.jar").path
            let expected = try java(["-cp", referenceArtifact + ":" + runtime, "HelloKt"])
            #expect(expected.exitCode == 0, "\(expected.stderr)")
            #expect(generated.stdout == expected.stdout)
            #expect(expected.stderr.isEmpty)
            let expectedReflection = try java(["-cp", referenceArtifact + ":" + runtime + ":" + root.path, "DelegateAnnotationProbe"])
            #expect(expectedReflection.exitCode == 0, "\(expectedReflection.stderr)")
            #expect(generatedReflection.stdout == expectedReflection.stdout)
            #expect(expectedReflection.stderr.isEmpty)
        }
    }
    @Test
    func delegateUseSiteAnnotationIsAcceptedOnTopLevelDelegates() throws {
        try withWorkspace { root in
            let source = #"""
            @Target(AnnotationTarget.FIELD)
            @Retention(AnnotationRetention.RUNTIME)
            annotation class Marker(val hash: Int)

            object Res

            @delegate:Marker(-1_991_362_839)
            val Res.label: String by lazy { "res" }

            @delegate:Marker(7)
            val plain: Int by lazy { 42 }

            fun main() { println(Res.label + plain) }
            """#
            let runtime = try m11Runtime()
            let classpath = runtime.components(separatedBy: ":")
            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: classpath)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let artifact = root.appendingPathComponent("hello.jar").path
            let probe = root.appendingPathComponent("TopLevelDelegateProbe.java")
            try """
            public class TopLevelDelegateProbe {
                public static void main(String[] args) throws ReflectiveOperationException {
                    HelloKt.main();
                    Marker label = HelloKt.class.getDeclaredField("label$delegate").getAnnotation(Marker.class);
                    Marker plain = HelloKt.class.getDeclaredField("plain$delegate").getAnnotation(Marker.class);
                    System.out.println(label.hash() + " " + plain.hash());
                }
            }
            """.write(to: probe, atomically: true, encoding: .utf8)
            let javaCompile = try javac(["-cp", artifact + ":" + runtime, "-d", root.path, probe.path])
            try #require(javaCompile.exitCode == 0, "\(javaCompile.stderr)")
            let run = try java(["-cp", artifact + ":" + runtime + ":" + root.path, "TopLevelDelegateProbe"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "res42\n-1991362839 7\n")
        }
    }

    @Test
    func delegateUseSiteAnnotationStillRejectsPropertiesWithoutDelegate() throws {
        try withWorkspace { root in
            let source = #"""
            @Target(AnnotationTarget.FIELD)
            annotation class Marker

            @delegate:Marker val plain: Int = 1

            fun main() { println(plain) }
            """#
            let runtime = try m11Runtime()
            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: runtime.components(separatedBy: ":"))
            #expect(compiled.0 != 0)
            #expect(compiled.1.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" })
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmOverloadsExposeDefaultsToJava() throws {
        try withWorkspace { root in
            let source = #"""
            @JvmOverloads fun topLevel(base: Int = 6, increment: Int = 1): Int = base + increment

            class Box {
                @JvmOverloads fun value(a: Int = 40, b: Int = 2): Int = a + b
                @JvmOverloads fun boundary(a: Int = 10, required: Int, tail: Int = 3): Int = a + required + tail
                fun ordinary(a: Int = 40, b: Int = 2): Int = a + b
                @JvmOverloads fun noDefaults(value: Int): Int = value
            }

            fun main() {
                val box = Box()
                println(box.value())
                println(box.value(40))
                println(box.value(40, 2))
                println(box.ordinary())
                println(box.boundary(required = 5))
                println(topLevel())
            }
            """#
            let runtime = try m11Runtime()
            let runtimeEntries = runtime.split(separator: ":").map(String.init)
            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: runtimeEntries)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let artifact = root.appendingPathComponent("hello.jar").path
            let kotlinOutput = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(kotlinOutput.exitCode == 0, "\(kotlinOutput.stderr)")
            #expect(kotlinOutput.stdout == "42\n42\n42\n42\n18\n7\n")
            #expect(kotlinOutput.stderr.isEmpty)

            let probe = root.appendingPathComponent("Probe.java")
            try """
            public class Probe {
                private static void assertMissingMethod(String name, Class<?>... parameters) throws ReflectiveOperationException {
                    try {
                        Box.class.getDeclaredMethod(name, parameters);
                        throw new AssertionError("unexpected overload: " + name);
                    } catch (NoSuchMethodException expected) {
                    }
                }

                public static void main(String[] args) throws Exception {
                    Box box = new Box();
                    System.out.println(box.value());
                    System.out.println(box.value(40));
                    System.out.println(box.value(40, 2));
                    System.out.println(HelloKt.topLevel());
                    System.out.println(HelloKt.topLevel(6));
                    System.out.println(HelloKt.topLevel(6, 1));
                    System.out.println(box.boundary(5));
                    System.out.println(box.boundary(10, 5));
                    System.out.println(box.boundary(10, 5, 9));
                    System.out.println(box.ordinary(40, 2));
                    System.out.println(Class.forName("Box").getDeclaredMethod("value").invoke(box));
                    assertMissingMethod("ordinary");
                    assertMissingMethod("ordinary", int.class);
                    assertMissingMethod("noDefaults");
                }
            }
            """.write(to: probe, atomically: true, encoding: .utf8)
            let javaCompile = try javac(["-cp", artifact + ":" + runtime, "-d", root.path, probe.path])
            try #require(javaCompile.exitCode == 0, "\(javaCompile.stderr)")

            let generatedConsumer = try java(["-cp", artifact + ":" + runtime + ":" + root.path, "Probe"])
            #expect(generatedConsumer.exitCode == 0, "\(generatedConsumer.stderr)")
            #expect(generatedConsumer.stdout == "42\n42\n42\n7\n7\n7\n18\n18\n24\n42\n42\n")
            #expect(generatedConsumer.stderr.isEmpty)

            let reference = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let referenceJar = root.appendingPathComponent("reference.jar").path
            let referenceKotlinOutput = try java(["-cp", referenceJar + ":" + runtime, "HelloKt"])
            #expect(referenceKotlinOutput.exitCode == 0, "\(referenceKotlinOutput.stderr)")
            #expect(referenceKotlinOutput.stdout == kotlinOutput.stdout)

            let referenceConsumer = try java(["-cp", referenceJar + ":" + runtime + ":" + root.path, "Probe"])
            #expect(referenceConsumer.exitCode == 0, "\(referenceConsumer.stderr)")
            #expect(referenceConsumer.stdout == generatedConsumer.stdout)
            #expect(referenceConsumer.stderr.isEmpty)
        }
    }

    @Test
    func jvmOverloadsRejectsConstructorUseOutsideFunctionScope() throws {
        try withWorkspace { root in
            let result = try compile(
                "class Box @JvmOverloads constructor(value: Int = 1, other: Int = 2)",
                root: root,
                mode: .jvmJar
            )
            #expect(result.0 == 1)
            #expect(
                result.1.contains { $0.code == "KSWIFTK-JVM-0001" && $0.message == "JVM @JvmOverloads currently supports functions only." },
                "\(result.1.map { ($0.code, $0.message) })"
            )
        }
    }
}
#endif

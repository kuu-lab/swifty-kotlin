#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func topLevelGenericExtensionPropertiesMatchKotlinAndJava(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            val <T> List<T>.lastValue: T get() = this[size - 1]
            val <T : CharSequence> T.tailChar: Char get() = this[length - 1]
            var <T> MutableList<T>.lastSlot: T
                get() = this[size - 1]
                set(value) { this[size - 1] = value }
            val String.bracketed: String get() = "[$this]"

            fun main() {
                println(listOf(1, 2, 3).lastValue)
                println(listOf("a", "b").lastValue)
                println("Kotlin".tailChar)
                val values = mutableListOf("first", "last")
                println(values.lastSlot)
                values.lastSlot = "changed"
                println(values.lastSlot)
                println("JVM".bracketed)
            }
            """
            let compiled = try compile(source, root: root, mode: mode)
            let diagnostics = compiled.1.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            try #require(compiled.0 == 0, "Unexpected compiler diagnostics: \(diagnostics)")

            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let generated = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            let referenceKotlinCompilation = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            try #require(referenceKotlinCompilation.exitCode == 0, "Kotlin reference compilation failed: \(referenceKotlinCompilation.stderr)")
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(generated.stdout == "3\nb\nn\nlast\nchanged\n[JVM]\n")
            #expect(generated.stdout == reference.stdout)
            #expect(generated.stderr.isEmpty)
            #expect(reference.stderr.isEmpty)

            let consumerSource = root.appendingPathComponent("JavaConsumer.java")
            try """
            import java.lang.reflect.Method;
            import java.lang.reflect.ParameterizedType;
            import java.lang.reflect.Type;
            import java.lang.reflect.TypeVariable;
            import java.lang.reflect.WildcardType;
            import java.util.ArrayList;
            import java.util.Arrays;
            import java.util.List;

            public final class JavaConsumer {
                private static <T> T last(List<T> values) {
                    return HelloKt.getLastValue(values);
                }

                private static void verifySignatures() throws Exception {
                    Method getter = HelloKt.class.getDeclaredMethod("getLastValue", List.class);
                    TypeVariable<Method>[] getterParameters = getter.getTypeParameters();
                    if (getterParameters.length != 1 || !"T".equals(getterParameters[0].getName())) {
                        throw new AssertionError("Missing generic getter type parameter: " + getter.toGenericString());
                    }
                    if (!getter.getGenericReturnType().equals(getterParameters[0])) {
                        throw new AssertionError("Generic return type was not preserved: " + getter.toGenericString());
                    }
                    Type receiver = getter.getGenericParameterTypes()[0];
                    if (!(receiver instanceof ParameterizedType parameterized)
                            || parameterized.getRawType() != List.class) {
                        throw new AssertionError("Missing generic List receiver: " + getter.toGenericString());
                    }
                    Type argument = parameterized.getActualTypeArguments()[0];
                    if (!(argument instanceof WildcardType wildcard)
                            || !Arrays.equals(wildcard.getUpperBounds(), new Type[] {getterParameters[0]})) {
                        throw new AssertionError("List receiver variance did not match Kotlin: " + getter.toGenericString());
                    }

                    Method setter = HelloKt.class.getDeclaredMethod("setLastSlot", List.class, Object.class);
                    TypeVariable<Method>[] setterParameters = setter.getTypeParameters();
                    if (setterParameters.length != 1
                            || !setter.getGenericParameterTypes()[1].equals(setterParameters[0])) {
                        throw new AssertionError("Missing generic setter signature: " + setter.toGenericString());
                    }

                    Method bounded = HelloKt.class.getDeclaredMethod("getTailChar", CharSequence.class);
                    TypeVariable<Method>[] boundedParameters = bounded.getTypeParameters();
                    if (boundedParameters.length != 1
                            || !Arrays.equals(boundedParameters[0].getBounds(), new Type[] {CharSequence.class})) {
                        throw new AssertionError("Generic upper bound was not preserved: " + bounded.toGenericString());
                    }
                }

                public static void main(String[] args) throws Exception {
                    verifySignatures();
                    System.out.println(last(List.of(1, 2, 3)));
                    System.out.println(last(List.of("a", "b")));
                    System.out.println(HelloKt.getTailChar("Java"));
                    List<String> values = new ArrayList<>(List.of("first", "last"));
                    System.out.println(HelloKt.getLastSlot(values));
                    HelloKt.setLastSlot(values, "changed");
                    System.out.println(HelloKt.getLastSlot(values));
                    System.out.println(HelloKt.getBracketed("JVM"));
                }
            }
            """.write(to: consumerSource, atomically: true, encoding: .utf8)

            let candidateConsumer = root.appendingPathComponent("candidate-java")
            let referenceConsumer = root.appendingPathComponent("reference-java")
            try FileManager.default.createDirectory(at: candidateConsumer, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: referenceConsumer, withIntermediateDirectories: true)
            let candidateClasspath = artifact + ":" + runtime
            let referenceClasspath = root.appendingPathComponent("reference.jar").path + ":" + runtime
            let candidateCompilation = try javac([
                "-cp", candidateClasspath, "-d", candidateConsumer.path, consumerSource.path,
            ])
            try #require(candidateCompilation.exitCode == 0, "Java consumer compilation failed: \(candidateCompilation.stderr)")
            let referenceJavaCompilation = try javac([
                "-cp", referenceClasspath, "-d", referenceConsumer.path, consumerSource.path,
            ])
            try #require(referenceJavaCompilation.exitCode == 0, "Java reference compilation failed: \(referenceJavaCompilation.stderr)")

            let candidateExecution = try java([
                "-cp", candidateConsumer.path + ":" + candidateClasspath, "JavaConsumer",
            ])
            let referenceExecution = try java([
                "-cp", referenceConsumer.path + ":" + referenceClasspath, "JavaConsumer",
            ])
            #expect(candidateExecution.stdout == "3\nb\na\nlast\nchanged\n[JVM]\n")
            #expect(candidateExecution.stdout == referenceExecution.stdout)
            #expect(candidateExecution.stderr.isEmpty)
            #expect(referenceExecution.stderr.isEmpty)
        }
    }

    @Test
    func genericPropertyWithoutExtensionReceiverIsRejectedBySema() throws {
        try withWorkspace { root in
            let result = try compile("val <T> invalid: T get() = null as T", root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.code == "KSWIFTK-SEMA-0005" }, "Expected generic non-extension property rejection: \(result.1)")
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func iterableFlattenIsAvailableInOwnStdlibJarAndJava() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = #"""
            fun <T> flattenGeneric(values: Iterable<Iterable<T>>): List<T> = values.flatten()

            fun main() {
                println(listOf(listOf(1), listOf(2, 3)).flatten())
                println(flattenGeneric(listOf(emptyList<Int>(), listOf(4), emptyList(), listOf(5, 6))))
                println(flattenGeneric(listOf(emptyList<String>(), listOf("x"))))
            }
            """#
            let app = try m22Build(root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [library.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let kotlin = try java(["-cp", app.0.path + ":" + library.path, "MainKt"])
            #expect(kotlin.stdout == "[1, 2, 3]\n[4, 5, 6]\n[x]\n")
            #expect(kotlin.stderr.isEmpty)
            let appBytecode = try javap(["-classpath", app.0.path + ":" + library.path, "-c", "MainKt"])
            #expect(appBytecode.stdout.contains("kotlin/collections/CollectionsKt.flatten"))

            let abi = try javap(["-classpath", library.path, "-p", "-s", "-v", "kotlin.collections.CollectionsKt"])
            try #require(abi.stdout.contains("flatten("), "CollectionsKt flatten ABI is missing")
            let flattenMethod = abi.stdout.components(separatedBy: "\n\n").first { $0.contains("flatten(") } ?? ""
            #expect(flattenMethod.contains("Signature:"))
            #expect(abi.stdout.contains("kotlin.Metadata"))

            let javaSource = #"""
            import java.util.Arrays;
            import java.util.Collections;
            import java.util.List;
            import kotlin.collections.CollectionsKt;

            public class JavaConsumer {
                public static void main(String[] args) {
                    kotlin.Metadata metadata = CollectionsKt.class.getAnnotation(kotlin.Metadata.class);
                    if (metadata == null || !Arrays.asList(metadata.d2()).contains("flatten")) {
                        throw new AssertionError("flatten is missing from Kotlin metadata");
                    }
                    try {
                        java.lang.reflect.Method flatten = CollectionsKt.class.getMethod("flatten", Iterable.class);
                        java.lang.reflect.Type receiverType = flatten.getGenericParameterTypes()[0];
                        if (!(receiverType instanceof java.lang.reflect.ParameterizedType)
                            || !receiverType.getTypeName().contains("T")) {
                            throw new AssertionError("flatten is missing its generic JVM signature");
                        }
                    } catch (NoSuchMethodException exception) {
                        throw new AssertionError(exception);
                    }
                    List<List<Integer>> values = Arrays.asList(
                        Arrays.asList(1), Collections.<Integer>emptyList(), Arrays.asList(2, 3)
                    );
                    List<Integer> flattened = CollectionsKt.flatten(values);
                    System.out.println(flattened);
                }
            }
            """#
            try javaSource.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try javac(["--release", "8", "-Xlint:unchecked", "-Werror", "-classpath", library.path, "JavaConsumer.java"])
            let javaConsumer = try java(["-cp", root.path + ":" + library.path, "JavaConsumer"])
            #expect(javaConsumer.stdout == "[1, 2, 3]\n")
            #expect(javaConsumer.stderr.isEmpty)

            let invalid = try m22Build(
                root: root,
                sources: [("Invalid.kt", "fun invalidFlatten(): List<Int> = listOf(1).flatten()")],
                name: "invalid.jar",
                classpath: [library.path]
            )
            #expect(invalid.1 != 0)
            #expect(invalid.2.contains { $0.code == "KSWIFTK-SEMA-0024" })
        }
    }
}
#endif

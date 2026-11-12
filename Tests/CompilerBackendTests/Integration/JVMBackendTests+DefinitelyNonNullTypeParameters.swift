#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func definitelyNonNullTypeParametersPreserveJvmAndJavaContracts(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            fun <T> nonNull(value: T & Any): T & Any = value
            fun <T> identity(value: T): T = value
            fun main() {
                println(nonNull<String>("ok"))
                println(identity<String?>(null) ?: "ordinary-null")
            }
            """
            try runM11(source, expected: "ok\nordinary-null\n", mode: mode, root: root)

            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let consumerSource = """
            public final class DefinitelyNonNullConsumer {
                public static void main(String[] args) {
                    System.out.println(HelloKt.nonNull("java"));
                    try {
                        HelloKt.nonNull(null);
                        System.out.println("accepted-null");
                    } catch (NullPointerException expected) {
                        System.out.println("rejected-null");
                    }
                }
            }
            """
            let javaFile = root.appendingPathComponent("DefinitelyNonNullConsumer.java")
            try consumerSource.write(to: javaFile, atomically: true, encoding: .utf8)
            let javaOutput = root.appendingPathComponent("java-consumer")
            try FileManager.default.createDirectory(at: javaOutput, withIntermediateDirectories: true)
            _ = try javac(["-cp", artifact + ":" + runtime, "-d", javaOutput.path, javaFile.path])
            let consumer = try java(["-cp", javaOutput.path + ":" + artifact + ":" + runtime, "DefinitelyNonNullConsumer"])
            #expect(consumer.stdout == "java\nrejected-null\n")
            #expect(consumer.stderr.isEmpty)

            let kotlinConsumerSource = """
            fun main() {
                val value: String = nonNull<String?>("kotlin")
                println(value.length)
            }
            """
            try kotlinConsumerSource.write(to: root.appendingPathComponent("KotlinConsumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["KotlinConsumer.kt", "-cp", artifact + ":" + runtime, "-d", "kotlin-consumer.jar"], root: root)

            let nullableKotlinConsumerSource = """
            fun main() { println(nonNull<String?>(null)) }
            """
            try nullableKotlinConsumerSource.write(to: root.appendingPathComponent("KotlinNullableConsumer.kt"), atomically: true, encoding: .utf8)
            do {
                _ = try jvmTool("kotlinc", ["KotlinNullableConsumer.kt", "-cp", artifact + ":" + runtime, "-d", "kotlin-nullable-consumer.jar"], root: root)
                Issue.record("kotlinc accepted a nullable argument when consuming the definitely non-null JVM signature")
            } catch CommandRunnerError.nonZeroExit(let error) {
                #expect(error.stderr.localizedCaseInsensitiveContains("null cannot be a value of a non-null type"), "\(error.stderr)")
            }

            let nullableArgument = """
            fun <T> nonNull(value: T & Any): T & Any = value
            fun main() { println(nonNull<String?>(null)) }
            """
            let invalid = try compile(nullableArgument, root: root, mode: .jvmJar)
            #expect(invalid.0 == 1, "\(invalid.1.map(\.message))")
            #expect(!invalid.1.contains { $0.code == "KSWIFTK-JVM-0001" })
            #expect(!invalid.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })

            do {
                _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "invalid.jar"], root: root)
                Issue.record("kotlinc accepted a nullable argument for a definitely non-null parameter")
            } catch CommandRunnerError.nonZeroExit(let error) {
                #expect(error.stderr.localizedCaseInsensitiveContains("null cannot be a value of a non-null type"), "\(error.stderr)")
            }
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    func kotlinMetadataJar() throws -> String {
        let compiler = URL(fileURLWithPath: CommandRunner.resolveExecutable("kotlinc", fallback: "/usr/bin/kotlinc")).resolvingSymlinksInPath()
        let home = compiler.deletingLastPathComponent().deletingLastPathComponent()
        let library = [home.appendingPathComponent("lib"), home.appendingPathComponent("libexec/lib")]
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("kotlin-metadata-jvm.jar").path) }
        let jar = library?.appendingPathComponent("kotlin-metadata-jvm.jar").path
        try #require(jar.map { FileManager.default.fileExists(atPath: $0) } == true, "Missing Kotlin metadata JVM library")
        return try #require(jar)
    }

    @Test
    func typeAliasAnnotationsMatchKotlinJvmMetadata() throws {
        let source = """
        @Target(AnnotationTarget.TYPEALIAS)
        annotation class Mark

        @Target(AnnotationTarget.TYPEALIAS)
        annotation class Labeled(val value: String = "default")

        @Target(AnnotationTarget.TYPEALIAS)
        @Retention(AnnotationRetention.BINARY)
        annotation class BinaryMark(val value: Int)

        @Target(AnnotationTarget.TYPEALIAS)
        @Retention(AnnotationRetention.SOURCE)
        annotation class SourceMark(val value: String)

        @Mark typealias Name = String
        @Labeled typealias Defaulted = String
        @Labeled("custom") typealias Named = Int
        @BinaryMark(7) typealias BinaryName = Long
        @SourceMark("source") typealias SourceOnly = Boolean
        typealias Plain = Char

        fun aliasValue(): Name = "ok"
        fun main() { val name: Name = aliasValue(); println(name) }
        """

        try withWorkspace { root in
            let compilation = try compile(source, root: root, mode: .jvmJar)
            try #require(compilation.0 == 0, "\(compilation.1.map(\.message))")

            let artifact = root.appendingPathComponent("hello.jar")
            let runtime = try m11Runtime()
            let generatedRun = try java(["-cp", artifact.path + ":" + runtime, "HelloKt"])
            #expect(generatedRun.exitCode == 0, "\(generatedRun.stderr)")
            #expect(generatedRun.stdout == "ok\n")
            #expect(generatedRun.stderr.isEmpty)

            let referenceCompile = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            #expect(referenceCompile.exitCode == 0, "\(referenceCompile.stderr)")
            let referenceRun = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(referenceRun.exitCode == 0, "\(referenceRun.stderr)")
            #expect(referenceRun.stdout == generatedRun.stdout)

            let inspector = """
            import kotlin.metadata.jvm.KotlinClassMetadata

            fun main(args: Array<String>) {
                val metadata = Class.forName(args[0]).getAnnotation(Metadata::class.java)
                val facade = KotlinClassMetadata.readStrict(metadata) as KotlinClassMetadata.FileFacade
                for (alias in facade.kmPackage.typeAliases.sortedBy { it.name }) {
                    println("${alias.name}:${alias.annotations}")
                }
            }
            """
            try inspector.write(to: root.appendingPathComponent("InspectMetadata.kt"), atomically: true, encoding: .utf8)
            let metadataJar = try kotlinMetadataJar()
            let inspectorCompile = try jvmTool("kotlinc", ["InspectMetadata.kt", "-cp", metadataJar, "-d", "inspector.jar"], root: root)
            #expect(inspectorCompile.exitCode == 0, "\(inspectorCompile.stderr)")

            let inspectorPath = root.appendingPathComponent("inspector.jar").path
            let generatedMetadata = try java(["-cp", inspectorPath + ":" + artifact.path + ":" + runtime + ":" + metadataJar, "InspectMetadataKt", "HelloKt"])
            let referenceMetadata = try java(["-cp", inspectorPath + ":" + root.appendingPathComponent("reference.jar").path + ":" + runtime + ":" + metadataJar, "InspectMetadataKt", "HelloKt"])
            #expect(generatedMetadata.exitCode == 0, "\(generatedMetadata.stderr)")
            #expect(referenceMetadata.exitCode == 0, "\(referenceMetadata.stderr)")
            #expect(generatedMetadata.stdout == referenceMetadata.stdout)
            #expect(generatedMetadata.stdout.trimmingCharacters(in: .newlines) == """
            BinaryName:[@BinaryMark(value = IntValue(7))]
            Defaulted:[@Labeled()]
            Name:[@Mark()]
            Named:[@Labeled(value = StringValue("custom"))]
            Plain:[]
            SourceOnly:[]
            """)

            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    String value = HelloKt.aliasValue();
                    if (!value.equals("ok")) throw new AssertionError(value);
                    System.out.println(value);
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            let consumerClasses = root.appendingPathComponent("java-consumer")
            try FileManager.default.createDirectory(at: consumerClasses, withIntermediateDirectories: true)
            let javaCompilation = try javac(["-cp", artifact.path + ":" + runtime, "-d", consumerClasses.path, root.appendingPathComponent("JavaConsumer.java").path])
            #expect(javaCompilation.exitCode == 0, "\(javaCompilation.stderr)")
            let javaConsumer = try java(["-cp", artifact.path + ":" + runtime + ":" + consumerClasses.path, "JavaConsumer"])
            #expect(javaConsumer.exitCode == 0, "\(javaConsumer.stderr)")
            #expect(javaConsumer.stdout == "ok\n")

            try "fun main() { val value: Name = aliasValue(); println(value) }".write(to: root.appendingPathComponent("KotlinConsumer.kt"), atomically: true, encoding: .utf8)
            let kotlinCompilation = try jvmTool("kotlinc", ["KotlinConsumer.kt", "-cp", artifact.path + ":" + runtime, "-d", "kotlin-consumer.jar"], root: root)
            #expect(kotlinCompilation.exitCode == 0, "\(kotlinCompilation.stderr)")
            let kotlinConsumer = try java(["-cp", root.appendingPathComponent("kotlin-consumer.jar").path + ":" + artifact.path + ":" + runtime, "KotlinConsumerKt"])
            #expect(kotlinConsumer.exitCode == 0, "\(kotlinConsumer.stderr)")
            #expect(kotlinConsumer.stdout == "ok\n")
        }
    }

    @Test
    func typeAliasAnnotationsWithInvalidTargetAreRejected() throws {
        let source = """
        @Target(AnnotationTarget.FUNCTION)
        annotation class FunctionMark
        @FunctionMark typealias InvalidName = String
        fun main() {}
        """

        try withWorkspace { root in
            let compilation = try compile(source, root: root, mode: .jvmJar)
            #expect(compilation.0 == 1)
            #expect(compilation.1.contains { $0.severity == .error && $0.message.contains("type alias") })
            #expect(!compilation.1.contains { $0.message.contains("Unsupported JVM typealias declaration") })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))

            do {
                _ = try jvmTool("kotlinc", ["hello.kt", "-d", "invalid-reference.jar"], root: root)
                Issue.record("kotlinc accepted a function-only annotation on a typealias")
            } catch CommandRunnerError.nonZeroExit(let result) {
                #expect(result.stderr.localizedCaseInsensitiveContains("annotation"))
            }
        }
    }
}
#endif

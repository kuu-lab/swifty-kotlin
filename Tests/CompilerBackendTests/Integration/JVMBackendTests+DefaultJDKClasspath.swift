#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func resolvesDefaultJDKModuleClassesAndRunsJavaConsumer(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            import java.math.BigInteger
            import java.nio.ByteBuffer
            import java.sql.Date
            import java.time.LocalDate
            import java.util.Base64

            fun main() {
                println(BigInteger("123").add(BigInteger("1")))
                println(Base64.getEncoder().encodeToString(byteArrayOf(65, 66)))
                val date = LocalDate.of(2024, 2, 28).plusDays(1)
                println(date)
                println(Date.valueOf(date))
                val buffer = ByteBuffer.allocate(4)
                buffer.putInt(42)
                buffer.flip()
                println(buffer.int)
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let appArguments = mode == .jvmJar
                ? ["-jar", artifact.path]
                : ["-cp", artifact.path, "HelloKt"]
            let execution = try java(appArguments)
            let expected = "124\nQUI=\n2024-02-29\n2024-02-29\n42\n"
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)

            let consumerSource = root.appendingPathComponent("JdkConsumer.java")
            let consumerClasses = root.appendingPathComponent("consumer", isDirectory: true)
            try FileManager.default.createDirectory(at: consumerClasses, withIntermediateDirectories: true)
            try """
            public final class JdkConsumer {
                public static void main(String[] args) {
                    HelloKt.main(args);
                }
            }
            """.write(to: consumerSource, atomically: true, encoding: .utf8)
            let compilation = try javac([
                "-classpath", artifact.path,
                "-d", consumerClasses.path,
                consumerSource.path,
            ])
            #expect(compilation.exitCode == 0, "\(compilation.stderr)")
            guard compilation.exitCode == 0 else { return }
            let consumer = try java([
                "-classpath", artifact.path + ":" + consumerClasses.path,
                "JdkConsumer",
            ])
            #expect(consumer.exitCode == 0, "\(consumer.stderr)")
            #expect(consumer.stdout == expected)
            #expect(consumer.stderr.isEmpty)
        }
    }

    @Test
    func rejectsMissingJDKTypeFromDefaultClasspath() throws {
        try withWorkspace { root in
            let result = try compile(
                "import java.math.NoSuchBigInteger\nfun main() { println(NoSuchBigInteger.ZERO) }",
                root: root,
                mode: .jvmJar
            )
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-UNRESOLVED-IMPORT" })
        }
    }
}
#endif

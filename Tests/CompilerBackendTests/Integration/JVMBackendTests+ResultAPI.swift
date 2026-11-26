#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func resultApiCompilesAndRunsAgainstBundledJvmStdlib(mode: EmitMode) throws {
        try withWorkspace { root in
            let runtime = try m11Runtime()
            let library = try ownStdlibLibrary()

            let source = """
            fun main() {
                val failure = runCatching { 1 / 0 }
                println(failure.isFailure)
                println(failure.exceptionOrNull() != null)
                println(Result.success(1).getOrNull())
                println(Result.success(1).getOrDefault(-1))
                println(Result.failure<Int>(IllegalStateException("failed")).getOrElse { -2 })
                println(Result.success(1).map { it + 1 }.getOrNull())
                println(failure.map { it + 1 }.isFailure)
                println(Result.success(1).fold({ it + 1 }, { -3 }))
                println(failure.fold({ it + 1 }, { -3 }))
                println("hello".runCatching { length + 1 }.getOrThrow())
                println("hello".runCatching { throw RuntimeException("boom") }.isFailure)
            }
            """
            let app = try m22Build(
                root: root,
                sources: [("ResultApi.kt", source)],
                name: mode == .jvmJar ? "result-api.jar" : "result-api-classes",
                mode: mode,
                classpath: [library.path]
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let expected = "true\ntrue\n1\n1\n-2\n2\ntrue\n2\n-3\n6\ntrue\n"
            let execution = try java(["-cp", app.0.path + ":" + runtime, "ResultApiKt"])
            #expect(execution.exitCode == 0, "stderr: \(execution.stderr)")
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)

            let ownExecution = try java(["-cp", app.0.path + ":" + library.path, "ResultApiKt"])
            #expect(ownExecution.exitCode == 0, "stderr: \(ownExecution.stderr)")
            #expect(ownExecution.stdout == expected)
            #expect(ownExecution.stderr.isEmpty)

            let foreignConsumer = try jvmTool(
                "kotlinc",
                ["-no-stdlib", "-no-reflect", "-cp", library.path, "ResultApi.kt", "-d", "foreign-consumer.jar"],
                root: root
            )
            try #require(foreignConsumer.exitCode == 0, "\(foreignConsumer.stderr)")
            let foreignExecution = try java([
                "-cp", root.appendingPathComponent("foreign-consumer.jar").path + ":" + library.path, "ResultApiKt",
            ])
            #expect(foreignExecution.exitCode == 0, "stderr: \(foreignExecution.stderr)")
            #expect(foreignExecution.stdout == expected)
            #expect(foreignExecution.stderr.isEmpty)

            let consumerSource = """
            fun main() {
                println(runCatching { 42 }.getOrThrow())
                println(runCatching { throw RuntimeException("boom") }.isFailure)
            }
            """
            try consumerSource.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let minimalConsumer = try jvmTool(
                "kotlinc",
                ["-no-stdlib", "-no-reflect", "-cp", library.path, "Consumer.kt", "-d", "minimal-consumer.jar"],
                root: root
            )
            try #require(minimalConsumer.exitCode == 0, "\(minimalConsumer.stderr)")
            let consumerExecution = try java([
                "-cp", root.appendingPathComponent("minimal-consumer.jar").path + ":" + library.path, "ConsumerKt",
            ])
            #expect(consumerExecution.exitCode == 0, "stderr: \(consumerExecution.stderr)")
            #expect(consumerExecution.stdout == "42\ntrue\n")
            #expect(consumerExecution.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["ResultApi.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java([
                "-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "ResultApiKt",
            ])
            #expect(reference.stdout == execution.stdout)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif

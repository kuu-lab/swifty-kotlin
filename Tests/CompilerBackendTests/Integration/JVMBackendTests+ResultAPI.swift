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

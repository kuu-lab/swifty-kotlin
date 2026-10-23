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
            }
            """
            let app = try m22Build(
                root: root,
                sources: [("ResultApi.kt", source)],
                name: mode == .jvmJar ? "result-api.jar" : "result-api-classes",
                mode: mode
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let execution = try java(["-cp", app.0.path + ":" + runtime, "ResultApiKt"])
            #expect(execution.exitCode == 0, "stderr: \(execution.stderr)")
            #expect(execution.stdout == "true\ntrue\n1\n1\n-2\n2\ntrue\n2\n-3\n")
            #expect(execution.stderr.isEmpty)

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

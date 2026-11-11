#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func resultMapPreservesUnconstrainedLambdaResult() throws {
        try withWorkspace { root in
            let result = try compile("""
            interface Outcome { val message: String }
            class Value(override val message: String) : Outcome
            fun execute() {}

            fun analyze(run: Boolean): Outcome {
                return if (run) {
                    runCatching { execute() }
                        .map { Value("success") }
                        .getOrElse { Value("failure") }
                } else Value("skipped")
            }

            fun main() {
                println(analyze(true).message)
                println(analyze(false).message)
            }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java([
                "-cp", root.appendingPathComponent("hello.jar").path + ":" + m11Runtime(), "HelloKt",
            ])
            #expect(execution.stdout == "success\nskipped\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

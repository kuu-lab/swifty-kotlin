#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func whenSubjectRetainsFlowThroughNullAndTypeConditions() throws {
        try withWorkspace { root in
            let result = try compile("""
            interface Problem { val message: String }
            class First : Problem { override val message: String = "first" }
            class Second : Problem { override val message: String = "second" }

            fun describe(value: Int?): String = when (val count = value) {
                null -> "missing"
                in -3..0 -> "negative"
                else -> "other"
            }

            fun message(problem: Problem?): String = when (problem) {
                is First, is Second -> problem.message
                else -> "none"
            }

            fun main() {
                println(describe(null))
                println(describe(-1))
                println(describe(4))
                println(message(First()))
                println(message(Second()))
                println(message(null))
            }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java([
                "-cp", root.appendingPathComponent("hello.jar").path + ":" + m11Runtime(), "HelloKt",
            ])
            #expect(execution.stdout == "missing\nnegative\nother\nfirst\nsecond\nnone\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

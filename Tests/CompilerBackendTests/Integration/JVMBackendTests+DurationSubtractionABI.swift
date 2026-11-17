#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledDurationSubtractionAndNegationLinkAgainstOwnStdlib() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.time.Duration
            import kotlin.time.Duration.Companion.milliseconds
            import kotlin.time.Duration.Companion.nanoseconds

            fun main() {
                val difference = 7.milliseconds - 5.nanoseconds
                println(difference.inWholeNanoseconds)
                println((-difference).inWholeNanoseconds)
                println((-Duration.ZERO).inWholeNanoseconds)
                println(-Duration.INFINITE)
                println(Duration.INFINITE - 5.nanoseconds)
                try {
                    println(Duration.INFINITE - Duration.INFINITE)
                } catch (_: IllegalArgumentException) {
                    println("undefined")
                }
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "6999995\n-6999995\n0\n-Infinity\nInfinity\nundefined\n")
        }
    }
}
#endif

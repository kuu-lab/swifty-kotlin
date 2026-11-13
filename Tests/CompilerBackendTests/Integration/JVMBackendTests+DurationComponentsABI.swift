#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledDurationComponentsUsePublishedJvmGetters() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.time.Duration
            import kotlin.time.Duration.Companion.milliseconds

            fun main() {
                val finite = 93_784_123.milliseconds
                for (duration in listOf(finite, -finite, Duration.ZERO, Duration.INFINITE, -Duration.INFINITE, 5_000_000_001_234L.milliseconds)) {
                    println(duration.toComponents { days, hours, minutes, seconds, nanos -> "$days,$hours,$minutes,$seconds,$nanos" })
                }
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            let expected = """
            1,2,3,4,123000000
            -1,-2,-3,-4,-123000000
            0,0,0,0,0
            9223372036854775807,0,0,0,0
            -9223372036854775808,0,0,0,0
            57870,8,53,21,234000000
            """
            #expect(result.stdout == expected + "\n")
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledGenericCoerceAtLeastUsesComparable() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            class Rank(val order: Int) : Comparable<Rank> {
                override fun compareTo(other: Rank): Int = order.compareTo(other.order)
            }

            fun main() {
                val low = Rank(1)
                val high = Rank(4)
                val equal = Rank(4)
                println(low.coerceAtLeast(high) === high)
                println(high.coerceAtLeast(low) === high)
                println(high.coerceAtLeast(equal) === high)
                println("b".coerceAtLeast("c"))
                println(2.coerceAtLeast(5))
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "true\ntrue\ntrue\nc\n5\n")
        }
    }
}
#endif

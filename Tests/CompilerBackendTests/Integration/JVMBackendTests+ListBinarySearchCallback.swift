import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func listBinarySearchCallbackRunsWithRepositoryStdlib() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            fun main() {
                val values = listOf(1, 3, 5, 7)
                println(values.binarySearch { it.compareTo(5) })
                println(values.binarySearch(1, 3) { it.compareTo(4) })
                println(values.binarySearch(fromIndex = 2) { it.compareTo(1) })
                println(values.binarySearch(2, 2) { error("empty range") })
                try {
                    values.binarySearch(3, 2) { error("invalid range") }
                } catch (_: IllegalArgumentException) {
                    println("reversed")
                }
                try {
                    values.binarySearch(-1) { error("invalid range") }
                } catch (_: IndexOutOfBoundsException) {
                    println("out of bounds")
                }
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.stdout == "2\n-3\n-3\n-3\nreversed\nout of bounds\n")
            #expect(result.stderr.isEmpty)
        }
    }
}

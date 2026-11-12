#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func listBinarySearchMatchesKotlincAndJavaConsumer() throws {
        let source = """
        fun search(values: List<Int>, key: Int): Int = values.binarySearch(key)

        fun main() {
            val values = listOf(1, 3, 5, 7)
            println(search(listOf(1, 3, 5), 3))
            println(values.binarySearch(4))
            println(emptyList<Int>().binarySearch(3))
            println(values.binarySearch { it - 7 })
            println(values.binarySearch(5, 2, 4))
            println(values.binarySearch(3, 2, 4))
            println(values.binarySearch(6, fromIndex = 1, toIndex = 3))

            val natural = Comparator<Int> { a, b -> a.compareTo(b) }
            println(values.binarySearch(5, natural))
            println(values.binarySearch(5, natural, fromIndex = 2, toIndex = 4))
            println(emptyList<Int>().binarySearch(4, 0, 0))
            println(values.binarySearch(100, 4, 4))

            try {
                values.binarySearch(3, 3, 2)
                println("range-order:accepted")
            } catch (error: IllegalArgumentException) {
                println("range-order:IllegalArgumentException")
            }
            try {
                values.binarySearch(3, -1, 2)
                println("negative-start:accepted")
            } catch (error: IndexOutOfBoundsException) {
                println("negative-start:IndexOutOfBoundsException")
            }
            try {
                values.binarySearch(3, 0, 5)
                println("past-end:accepted")
            } catch (error: IndexOutOfBoundsException) {
                println("past-end:IndexOutOfBoundsException")
            }
        }
        """
        let expected = """
        1
        -3
        -1
        3
        2
        -3
        -4
        2
        2
        -1
        -5
        range-order:IllegalArgumentException
        negative-start:IndexOutOfBoundsException
        past-end:IndexOutOfBoundsException

        """

        try withWorkspace { root in
            let runtime = try m11Runtime()
            let runtimeEntries = runtime.components(separatedBy: ":")
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: "app.jar",
                classpath: runtimeEntries
            )
            try #require(app.1 == 0, "KSwiftK diagnostics: \(app.2.map(\.message))")
            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["Main.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "MainKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)

            let javaConsumer = """
            public final class JavaConsumer {
                public static void main(String[] args) {
                    java.util.List<Integer> values = java.util.Arrays.asList(1, 3, 5);
                    System.out.println(MainKt.search(values, 3));
                }
            }
            """
            try javaConsumer.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-cp", app.0.path + ":" + runtime, "JavaConsumer.java"], root: root)
            let consumer = try java(["-cp", root.path + ":" + app.0.path + ":" + runtime, "JavaConsumer"])
            #expect(consumer.stdout == "1\n")
            #expect(consumer.stderr.isEmpty)
        }
    }
}
#endif

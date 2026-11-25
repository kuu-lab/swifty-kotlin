#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func groupingByFoldToRunsAgainstOfficialRuntime() throws {
        let source = #"""
        fun main() {
            val grouping = listOf("apple", "banana", "avocado", "blueberry", "cherry")
                .groupingBy { it.substring(0, 1) }

            val valueDestination = mutableMapOf("z" to 100)
            val valueFolded = grouping.foldTo(valueDestination, 0) { accumulator, element ->
                accumulator + element.length
            }
            println(valueFolded)
            println(valueFolded === valueDestination)

            val selectorDestination = mutableMapOf("z" to 100, "a" to 1)
            println(
                grouping.foldTo(
                    selectorDestination,
                    { key, element -> key.length + element.length },
                    { key, accumulator, element -> accumulator + key.length + element.length }
                )
            )
        }
        """#
        let expected = "{z=100, a=12, b=15, c=6}\ntrue\n{z=100, a=15, b=24, c=14}\n"

        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: .jvmJar)
            let diagnostics = compiled.1.map(\.message).joined(separator: "\n")
            try #require(compiled.0 == 0, "\(diagnostics)")

            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent("hello.jar").path
            let generated = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(generated.stdout == expected)
            #expect(generated.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(reference.stdout == generated.stdout)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif

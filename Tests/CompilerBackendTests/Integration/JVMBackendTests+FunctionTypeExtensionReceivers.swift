#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsExternalExtensionWithFunctionTypeReceiver() throws {
        try withWorkspace { root in
            let providerSource = """
            package dep

            fun ((Int) -> Int).applyTo(value: Int): Int = this(value)
            fun Map<String, (Int) -> Int>.applyMapped(key: String, transform: (Int) -> Int): Int =
                transform(getValue(key)(40))
            """
            let provider = root.appendingPathComponent("Provider.kt")
            let dependency = root.appendingPathComponent("provider.jar")
            try providerSource.write(to: provider, atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Provider.kt", "-d", "provider.jar"], root: root)

            let consumer = """
            import dep.applyTo

            fun main() {
                val addOne: (Int) -> Int = { it + 1 }
                println(addOne.applyTo(41))
            }
            """
            let result = try compile(consumer, root: root, mode: .jvmJar, classpath: [dependency.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let runtime = try m11Runtime()
            let candidate = root.appendingPathComponent("hello.jar").path
            let actual = try java(["-cp", "\(candidate):\(dependency.path):\(runtime)", "HelloKt"])
            #expect(actual.stdout == "42\n")
            #expect(actual.stderr.isEmpty)
        }
    }
}
#endif

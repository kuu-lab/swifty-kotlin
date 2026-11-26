#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func charDigitToIntOrNullExecutesWithoutExternalKotlinRuntime() throws {
        let source = """
        fun main() {
            println('z'.digitToIntOrNull())
            println('f'.digitToIntOrNull(16))
            println('g'.digitToIntOrNull(16))
            println('-'.digitToIntOrNull(10))
            try {
                println('5'.digitToIntOrNull(1))
            } catch (error: IllegalArgumentException) {
                println("invalid radix")
            }
        }
        """

        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar, includeJVMRuntime: true)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path
            let execution = try java(["-jar", jar])
            #expect(execution.stdout == """
            null
            15
            null
            null
            invalid radix

            """)
            #expect(execution.stderr.isEmpty)

            let referenceBuild = try jvmTool("kotlinc", ["hello.kt", "-include-runtime", "-d", "reference.jar"], root: root)
            try #require(referenceBuild.exitCode == 0, "\(referenceBuild.stderr)")
            let reference = try java(["-jar", root.appendingPathComponent("reference.jar").path])
            #expect(reference.stdout == execution.stdout)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif

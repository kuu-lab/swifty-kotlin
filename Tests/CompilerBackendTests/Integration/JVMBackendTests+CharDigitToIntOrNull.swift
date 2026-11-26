#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func charDigitToIntOrNullMatchesKotlinStdlib() throws {
        let runtime = try m11Runtime()
        let runtimeJars = runtime.split(separator: ":").map(String.init)
        let source = """
        fun main() {
            println('z'.digitToIntOrNull())
            println('f'.digitToIntOrNull(16))
            println('g'.digitToIntOrNull(16))
            println('-'.digitToIntOrNull(10))
        }
        """

        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar, classpath: runtimeJars)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path
            let execution = try java(["-cp", jar + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == """
            null
            15
            null
            null

            """)
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func integerArithmeticOverflowsBeforeContextualLongConversion(mode: EmitMode) throws {
        let source = """
        fun overflow(): Long = 2147483647 + 1
        fun main() {
            val sum: Long = 2147483647 + 1
            val product: Long = 100000 * 100000
            println(sum); println(overflow()); println(product)
            println(2147483647L + 1L)
            println(Long.MAX_VALUE + 1L); println(Long.MIN_VALUE - 1L)
            println('a' - 'b'); println('a' + 2); println('a' - 2)
            println(2 + 3); println(7.5 / 2.5)
        }
        """
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "-2147483648\n-2147483648\n1410065408\n2147483648\n-9223372036854775808\n9223372036854775807\n-1\nc\n_\n5\n3.0\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

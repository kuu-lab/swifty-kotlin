#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func charPredicatesResolveAndExecuteOnJVM() throws {
        let source = """
        fun main() {
            println('A'.isLetter())
            println('1'.isDigit())
            println(' '.isWhitespace())
            println('7'.isLetterOrDigit())
            println('A'.isLetterOrDigit())
            println('!'.isLetterOrDigit())
        }
        """
        let expected = "true\ntrue\ntrue\ntrue\ntrue\nfalse\n"
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: .jvmJar, root: root)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4741OfficialClasspathInlineCharFunctions(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            fun main() {
                println('5'.isDigit())
                println('a'.isLowerCase())
                println('A'.isUpperCase())
                println('a'.uppercaseChar())
                println('A'.lowercaseChar())
                println('a'.uppercase())
                println('A'.lowercase())
                println('ß'.uppercase())
                println('İ'.lowercase())
                println('a'.titlecase())
                println(' '.isWhitespace())
                println('a'.toFloat())
                val convert = Char::toFloat
                println(convert('a'))
                println('a'.equals('A', ignoreCase = true))
            }
            """
            let expected = "true\ntrue\ntrue\nA\na\nA\na\nSS\ni\u{307}\nA\ntrue\n97.0\n97.0\ntrue\n"
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func explicitCharStringPlusConcatenatesAndPreservesScalarControls(mode: EmitMode) throws {
        let source = """
        fun left(): Char { print("L"); return 'a' }
        fun right(): String { print("R"); return "bc" }
        fun main() {
            println('a'.plus("bc")); println('a' + "bc")
            println("a".plus("bc")); println(left().plus(right()))
            val present: Char? = 'a'
            val absent: Char? = null
            println(present?.plus("bc")); println(absent?.plus(right()))
            println('a'.plus(2)); println('a'.minus(2)); println('a'.minus('b'))
            println(2.plus(3)); println(7.5.div(2.5))
        }
        """
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "abc\nabc\nabc\nLRabc\nabc\nnull\nc\n_\n-1\n5\n3.0\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

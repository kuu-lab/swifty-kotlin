#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2886VarargCanAppearAlongsideOtherParameters(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = #"""
            fun f(x: Int, vararg rest: String) = "$x:${rest.size}"
            fun g(vararg xs: Int, last: Int) = xs.size + last
            fun main() {
                println(f(1, "a", "b"))
                println(f(1, *arrayOf("c", "d")))
                println(f(1))
                println(g(1, 2, last = 3))
                println(g(last = 4))
            }
            """#
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.stdout == "1:2\n1:2\n1:0\n5\n4\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

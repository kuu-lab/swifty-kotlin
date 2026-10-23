#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2880AnonymousObjectJavaClassNameMatchesKotlinc(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            interface I { fun f(): String }
            fun main() {
                val o = object : I { override fun f() = "x" }
                println("'${o.javaClass.simpleName}'")
                println("'${o.javaClass.name}'")
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let arguments = mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"]
            let execution = try java(arguments)
            #expect(execution.stdout == "''\n'HelloKt$main$o$1'\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

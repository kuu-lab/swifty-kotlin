#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    /// Regression for the emitClasses ordering fix: an anonymous object declared
    /// inside a member function only becomes eligible for emission while that
    /// member's body is built. It must still be emitted and runnable.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func anonymousObjectInsideMemberIsEmittedAndRuns(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            interface Greeter { fun greet(): String }
            class Factory {
                fun make(): Greeter = object : Greeter {
                    override fun greet(): String = "anon-ok"
                }
            }
            fun main() { println(Factory().make().greet()) }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let arguments = mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"]
            let execution = try java(arguments)
            #expect(execution.stdout == "anon-ok\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    /// Regression for the method-owner index: data-class synthetic lookups
    /// (`dataMethods`) and supertype bridge lookups (`bridges`) must keep working
    /// after methods are registered and replaced during emission.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func methodOwnerIndexPreservesDataClassAndDelegationBehavior(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
            interface Box<T> { fun get(): T }
            data class Item(val id: Int, val label: String)
            class StringBox(val s: String) : Box<String> {
                override fun get(): String = s
            }
            class DelegatingBox(b: Box<String>) : Box<String> by b
            fun main() {
                val item = Item(1, "x")
                println(item.copy(id = 2).component2())
                println(StringBox("hello").get())
                println(DelegatingBox(StringBox("world")).get())
            }
            """
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            guard result.0 == 0 else { return }
            let arguments = mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"]
            let execution = try java(arguments)
            #expect(execution.stdout == "x\nhello\nworld\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

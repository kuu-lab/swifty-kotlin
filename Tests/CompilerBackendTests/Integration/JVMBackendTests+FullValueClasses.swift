#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func fullValueClassesSupportAbstractInheritance(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = """
                abstract value class Base {
                    abstract val first: String
                    fun fakeOverridden(): String = first
                }
                abstract value class Child() : Base()
                class Concrete(override val first: String) : Child()
                @JvmInline value class InlineCount(val value: Int)
                fun main() {
                    println(Concrete("ok").fakeOverridden())
                    println(InlineCount(7).value)
                }
                """
            let result = try compile(source, root: root, mode: mode, flags: ["full-value-classes"])
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "ok\n7\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif

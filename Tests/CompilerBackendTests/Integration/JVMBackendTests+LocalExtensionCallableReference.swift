#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func unboundLocalExtensionReferenceReceivesExactlyOneReceiver(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                fun String.label(): String = this
                val reference = String::label
                println(reference("O"))
            }
            """, expected: "O\n", mode: mode, root: root)
        }
    }
}
#endif

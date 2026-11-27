#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kotlinStringInternUsesJDKMethod(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val a = "he" + "llo"
                println(a.intern() == "hello")
                println("already".intern() == "already")
            }
            """, expected: "true\ntrue\n", mode: mode, root: root)
        }
    }
}
#endif

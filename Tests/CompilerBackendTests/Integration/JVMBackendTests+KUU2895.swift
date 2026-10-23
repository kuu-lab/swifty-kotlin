#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaLangStaticMembersAndQualifiedArrayListConstructor(mode: EmitMode) throws {
        try assertJVM("""
        fun main() {
            println(System.getProperty("java.specification.version") != null)
            println(java.lang.System.getProperty("KSWIFTK_KUU2895_MISSING", "fallback"))
            println(Math.max(3, 4))
            println(Math.max(3L, 4L))
            println(Math.max(3.0, 4.0))
            println(Math.max(3.0f, 4.0f))
            println(Integer.parseInt("42"))
            println(Character.isDigit('5'))
            println(Character.isDigit(53))
            val list = java.util.ArrayList<Int>()
            println(list.size)
        }
        """, "true\nfallback\n4\n4\n4.0\n4.0\n42\ntrue\ntrue\n0\n", mode: mode)
    }
}
#endif

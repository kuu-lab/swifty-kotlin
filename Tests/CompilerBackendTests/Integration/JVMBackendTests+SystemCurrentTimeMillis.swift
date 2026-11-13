#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func javaSystemCurrentTimeMillis(mode: EmitMode) throws {
        try assertJVM("""
        fun main() {
            val before: Long = System.currentTimeMillis()
            val after: Long = java.lang.System.currentTimeMillis()
            println(before > 0L && after > 0L)
        }
        """, "true\n", mode: mode)
    }
}
#endif

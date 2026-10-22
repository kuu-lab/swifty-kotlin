#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func genericSignedIntegerBoundsAcceptFittingConstants(mode: EmitMode) throws {
        try assertJVM("""
        fun <T : Byte> byteEcho(v: T): T = v
        fun <T : Short> shortEcho(v: T): T = v
        fun <T : Long> longEcho(v: T): T = v
        fun <T : Byte?> nullableEcho(v: T): T = v
        fun <T> identity(v: T): T = v
        fun pick(v: Int): Int = 1
        fun <T : Byte> pick(v: T): String = "generic"
        fun main() {
            println(byteEcho(127)); println(byteEcho(-128))
            println(shortEcho(32767)); println(shortEcho(-32768))
            println(longEcho(1)); println(nullableEcho(1)); println(identity(1)); println(pick(1))
        }
        """, "127\n-128\n32767\n-32768\n1\n1\n1\n1\n", mode: mode)
    }
}
#endif

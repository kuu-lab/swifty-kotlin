#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func immutableComparablePrimitiveBoxesUseDirectComparison(mode: EmitMode) throws {
        try assertJVM("""
        class Custom : Comparable<Byte> { override fun compareTo(other: Byte): Int = -77 }
        fun <T : Comparable<T>> generic(a: T, b: T) = a.compareTo(b)
        fun unknown(): Comparable<Byte> { print("U"); return (-128).toByte() }
        fun source(): Byte { print("S"); return (-128).toByte() }
        fun argument(): Byte { print("A"); return 127.toByte() }
        fun receiver(): Comparable<Byte> { print("R"); return Custom() }
        fun main() {
            val byte: Comparable<Byte> = source()
            val short: Comparable<Short> = 32767.toShort()
            println(byte.compareTo(argument())); println(short.compareTo((-32768).toShort()))
            println(generic((-128).toByte(), 127.toByte()))
            var mutable: Comparable<Byte> = (-128).toByte()
            println(mutable.compareTo(127.toByte())); mutable = Custom()
            println(mutable.compareTo(127.toByte()))
            val value: Comparable<Byte> = unknown()
            println(value.compareTo(127.toByte()))
            val custom: Comparable<Byte> = Custom()
            println(custom.compareTo(127.toByte()))
            val captured: Comparable<Byte> = (-128).toByte()
            val closure: () -> Int = { captured.compareTo(127.toByte()) }
            println(closure())
            println(receiver().compareTo(argument()))
        }
        """, "SA-1\n1\n-255\n-255\n-77\nU-255\n-77\n-255\nRA-77\n", mode: mode)
    }
}
#endif

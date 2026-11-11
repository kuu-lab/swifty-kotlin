#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func customNumberSubclassDispatchesJvmConversionOverrides(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            class Whole(private val number: Int) : Number() {
                override fun toByte(): Byte = number.toByte()
                override fun toDouble(): Double = number.toDouble()
                override fun toFloat(): Float = number.toFloat()
                override fun toInt(): Int = number
                override fun toLong(): Long = number.toLong()
                override fun toShort(): Short = number.toShort()
            }

            class CustomConversions : Number() {
                override fun toByte(): Byte = 1
                override fun toShort(): Short = 2
                override fun toInt(): Int = 3
                override fun toLong(): Long = 4L
                override fun toFloat(): Float = 5.0f
                override fun toDouble(): Double = 6.0
            }

            fun printConversions(value: Number) {
                println(value.toByte())
                println(value.toShort())
                println(value.toInt())
                println(value.toLong())
                println(value.toFloat())
                println(value.toDouble())
            }

            fun main() {
                println(Whole(7).toInt())
                printConversions(Whole(7))
                printConversions(CustomConversions())
                val primitive: Number = 7
                printConversions(primitive)
            }
            """, expected: "7\n7\n7\n7\n7\n7.0\n7.0\n1\n2\n3\n4\n5.0\n6.0\n7\n7\n7\n7\n7.0\n7.0\n", mode: mode, root: root)
        }
    }
}
#endif

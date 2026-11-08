import java.lang.Byte
import java.lang.Character
import java.lang.Float
import java.lang.Integer
import java.lang.Long
import java.lang.Short

fun main() {
    val i = Integer(42)
    println(i)
    println(Integer("17"))
    println(Integer.valueOf(5))
    println(i == Integer(42))
    println(i == Integer(43))
    println(i.hashCode())

    val l = Long(1234567890123L)
    println(l)
    println(Long("9876543210"))
    println(Long.valueOf(5L))
    println(l == Long(1234567890123L))
    println(l.hashCode())

    val b = Byte(5.toByte())
    println(b)
    println(Byte("12"))
    println(Byte.valueOf(7.toByte()))

    val s = Short((-300).toShort())
    println(s)
    println(Short("-7"))

    val f = Float(1.5f)
    println(f)
    println(Float("2.5"))
    println(f == Float(1.5f))
    println(Float.valueOf(0.5f))

    val c = Character('x')
    println(c)
    println(Character.valueOf('y'))
    println(c == Character('x'))
    println(c == Character('z'))
    println(c.hashCode())
    println(Character.isDigit('5'))
}

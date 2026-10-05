import kotlin.experimental.and as bitAnd
import kotlin.experimental.or as bitOr
import kotlin.experimental.xor as bitXor
import kotlin.experimental.inv as bitInv

infix fun Byte.and(other: Byte): Byte = 42
infix fun Byte.or(other: Byte): Byte = 43
infix fun Byte.xor(other: Byte): Byte = 44
fun Byte.inv(): Byte = 45
infix fun Short.and(other: Short): String = "short and"
infix fun Short.or(other: Short): String = "short or"
infix fun Short.xor(other: Short): String = "short xor"
fun Short.inv(): String = "short inv"

fun main() {
    val b: Byte = 0x5A
    val mask: Byte = 0x0F
    val s: Short = 0x1234
    val wideMask: Short = 0xFF
    println(b and mask)
    println(b.or(mask))
    println(b.xor(mask))
    println(b.inv())
    println(s and wideMask)
    println(s.or(wideMask))
    println(s.xor(wideMask))
    println(s.inv())
    println(b bitAnd mask)
    println(b.bitOr(mask))
    println(b.bitXor(mask))
    println(b.bitInv())
    println(s bitAnd wideMask)
    println(s.bitOr(wideMask))
    println(s.bitXor(wideMask))
    println(s.bitInv())

    val nb: Byte? = b
    val ns: Short? = s
    println(nb?.and(mask))
    println(nb?.or(mask))
    println(nb?.xor(mask))
    println(nb?.inv())
    println(ns?.and(wideMask))
    println(ns?.or(wideMask))
    println(ns?.xor(wideMask))
    println(ns?.inv())
    println(nb?.bitAnd(mask))
    println(nb?.bitInv())
    println(ns?.bitOr(wideMask))
    println(ns?.bitInv())

    var calls: Int = 0
    fun operand(): Byte { calls += 1; return mask }
    val absent: Byte? = null
    println(absent?.and(operand()))
    println(absent?.bitAnd(operand()))
    println(absent?.inv())
    println(absent?.bitInv())
    println(calls)
}

// KUU-2061: package extensions preserve explicit and alias imports and engines.
import kotlin.random.Random
import kotlin.random.nextUInt
import kotlin.random.nextULong
import kotlin.random.nextUInt as uintBits
import kotlin.random.nextULong as ulongBits

fun main() {
    val direct = Random(7)
    val aliased = Random(7)
    println(direct.nextUInt() == aliased.uintBits())
    println(direct.nextUInt(until = 10u) == aliased.uintBits(until = 10u))
    println(direct.nextUInt(from = 10u, until = 20u) == aliased.uintBits(from = 10u, until = 20u))
    println(direct.nextUInt(30u..35u) == aliased.uintBits(30u..35u))
    println(direct.nextULong() == aliased.ulongBits())
    println(direct.nextULong(until = 10uL) == aliased.ulongBits(until = 10uL))
    println(direct.nextULong(from = 10uL, until = 20uL) == aliased.ulongBits(from = 10uL, until = 20uL))
    println(direct.nextULong(30uL..35uL) == aliased.ulongBits(30uL..35uL))
    println(Random.ulongBits(1uL) == 0uL)
    println(Random.Default.uintBits(1u) == 0u)
    val signed = Random(7)
    val unsigned = Random(7)
    println(signed.nextInt().toUInt() == unsigned.nextUInt())
    println(signed.nextLong().toULong() == unsigned.nextULong())
    try {
        direct.ulongBits(0uL)
        println("missing")
    } catch (e: IllegalArgumentException) {
        println("ulong bounds")
    }
    try {
        direct.uintBits(0u)
        println("missing")
    } catch (e: IllegalArgumentException) {
        println("uint bounds")
    }
}

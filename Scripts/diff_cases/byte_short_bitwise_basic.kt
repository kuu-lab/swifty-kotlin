import kotlin.experimental.and
import kotlin.experimental.inv
import kotlin.experimental.or
import kotlin.experimental.xor

fun main() {
    val a: Byte = 0b0110
    val b: Byte = 0b0011
    println(a and b)
    println(a or b)
    println(a xor b)
    println(a.inv())
    println(a.and(b))
    println(a.or(b))
    println(a.xor(b))

    val negative: Byte = -1
    val high: Byte = 0x70
    println(negative and high)
    println(negative or high)
    println(negative xor high)
    println(negative.inv())
    println(high.inv())

    val minByte: Byte = -128
    val maxByte: Byte = 127
    println(minByte.inv())
    println(maxByte.inv())
    println(minByte and maxByte)
    println(minByte or maxByte)
    println(minByte xor maxByte)

    val s: Short = 0b0110
    val t: Short = 0b0011
    println(s and t)
    println(s or t)
    println(s xor t)
    println(s.inv())
    println(s.and(t))
    println(s.or(t))
    println(s.xor(t))

    val negativeShort: Short = -1
    val highShort: Short = 0x7000
    println(negativeShort and highShort)
    println(negativeShort or highShort)
    println(negativeShort xor highShort)
    println(negativeShort.inv())
    println(highShort.inv())

    val minShort: Short = -32768
    val maxShort: Short = 32767
    println(minShort.inv())
    println(maxShort.inv())
    println(minShort and maxShort)
    println(minShort or maxShort)
    println(minShort xor maxShort)

    println((a and b).toInt())
    println((s or t).toInt())
    println(((a xor b) and a).toString())
    println((256.toByte()) and maxByte)
    println((65536.toShort()) or maxShort)
}

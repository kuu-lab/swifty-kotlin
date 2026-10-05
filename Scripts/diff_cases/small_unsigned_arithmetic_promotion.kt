fun tag(x: Byte) = "B:$x"
fun tag(x: Short) = "S:$x"
fun tag(x: Int) = "I:$x"
fun tag(x: Long) = "L:$x"
fun tag(x: UByte) = "UB:$x"
fun tag(x: UShort) = "US:$x"
fun tag(x: UInt) = "UI:$x"
fun tag(x: ULong) = "UL:$x"

fun main() {
    val a: UByte = 200u.toUByte()
    val c: UByte = 100u.toUByte()
    val d: UShort = 0xFFFFu.toUShort()
    val one: UShort = 1u.toUShort()
    val two: UShort = 2u.toUShort()

    println(tag(a * c))
    println(tag(a + c))
    println(tag(c - a))
    println(tag(a / c))
    println(tag(a % c))
    println(tag(d + one))
    println(tag(d * two))
    println(tag(one - d))
    println(tag(d / two))
    println(tag(d % two))

    println(tag(a.times(c)))
    println(tag(a.plus(c)))
    println(tag(c.minus(a)))
    println(tag(a.div(c)))
    println(tag(a.rem(c)))
    println(tag(d.plus(one)))
    println(tag(d.times(two)))
    println(tag(one.minus(d)))
    println(tag(d.div(two)))
    println(tag(d.rem(two)))

    println(tag(a + d))
    println(tag(d + a))
    println(tag(a * d))
    println(tag(d * a))
    println(tag(a + 1u))
    println(tag(1u + a))
    println(tag(d * 2u))
    println(tag(2u * d))
    println(tag(a + 1uL))
    println(tag(1uL + a))
    println(tag(d * 2uL))
    println(tag(2uL * d))

    val product: UInt = a * c
    val sum: UInt = d + one
    val largeProduct = d * d
    println(product)
    println(sum)
    println(tag(largeProduct))
    println(tag(largeProduct + largeProduct))
    println(tag(d * d * two))
    println((c - a).toLong())
    println((a + c).inv())
    println((d + one) shr 16)
    println((d + one) shl 32)

    // Bitwise operations and increments retain the small receiver's width.
    println(tag(a and c))
    println(tag(d xor one))
    println(tag(a.mod(c)))
    println(tag(d.mod(two)))
    var ub: UByte = 255u.toUByte()
    var us: UShort = 0u.toUShort()
    println(tag(++ub))
    println(tag(--us))
}

fun boolWhen(b: Boolean?) = when (b) { true -> "T"; false -> "F"; null -> "N" }

data class Point(val x: Int)

enum class Shade { RED, GREEN }

fun main() {
    println(boolWhen(true))
    println(boolWhen(false))
    println(boolWhen(null))

    val x: Boolean? = null
    println(when (x) { null -> "N"; true -> "T"; false -> "F" })
    println(when (x) { false -> "F"; else -> "other" })

    val i: Int? = null
    println(when (i) { 0 -> "zero"; null -> "N"; else -> "?" })

    val c: Char? = null
    println(when (c) { '\u0000' -> "nul"; null -> "N"; else -> "?" })

    // Plain `==`/`!=` on nullable primitives must stay null-aware too.
    val b1: Boolean? = null
    println(b1 == false)
    println(b1 == true)
    println(b1 != false)
    println(false != b1)

    val i1: Int? = null
    println(i1 == 0)
    println(i1 != 0)

    // Two nullable operands, including distinct boxed instances of an equal value.
    val a: Boolean? = true
    val b2: Boolean? = true
    println(a == b2)

    val n1: Int? = null
    val n2: Int? = null
    println(n1 == n2)

    val p1: Int? = 5
    val p2: Int? = 5
    println(p1 == p2)
    println(p1 != p2)

    // `!=` must be symmetric with `==` for other structural-equality cases
    // too: a data class compares by content, and Any-erased boxed primitives
    // compare by value, not by pointer identity.
    val f1: Point? = Point(1)
    val f2: Point? = Point(1)
    println(f1 != f2)
    println(f1 == f2)

    val any1: Any? = 5
    val any2: Any? = 5
    println(any1 != any2)

    val elem = Shade.values()[0]
    println(elem != Shade.RED)
    println(elem != Shade.GREEN)

    // Long?/ULong?/Double?/Float? are the only primitives whose full raw
    // (unboxed) value range coincides with the runtime null sentinel
    // (Long.MIN_VALUE, ULong 2^63, -0.0's bit pattern), so null-awareness
    // there needs to key off each operand's own boxing state, not its bits.
    val d: Double? = null
    println(d == 0.0)
    println(d != 0.0)
    val fl: Float? = null
    println(fl == 0.0f)
    println(fl != 0.0f)

    val nl1: Long? = null
    println(nl1 == Long.MIN_VALUE)
    println(nl1 != Long.MIN_VALUE)

    val bl1: Long? = Long.MIN_VALUE
    println(bl1 == Long.MIN_VALUE)
    println(bl1 != Long.MIN_VALUE)
    println(Long.MIN_VALUE == bl1)

    val bl2: Long? = Long.MIN_VALUE
    println(bl1 == bl2)

    val nd1: Double? = null
    println(nd1 == -0.0)
    val bd1: Double? = -0.0
    println(bd1 == -0.0)
    println(bd1 == 0.0)

    val nul1: ULong? = null
    val sentinelU = 9223372036854775808uL
    println(nul1 == sentinelU)
    val bul1: ULong? = sentinelU
    println(bul1 == sentinelU)
}
